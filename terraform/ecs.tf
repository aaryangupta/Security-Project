resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ─── Log groups ──────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}-app"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "pyrit" {
  name              = "/ecs/${var.project}-pyrit"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "tensorzero" {
  name              = "/ecs/${var.project}-tensorzero"
  retention_in_days = var.log_retention_days
}

# ─── Task definitions ────────────────────────────────────────────────────────

# App and TensorZero share a task, so the app reaches the gateway on localhost:3000.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.app_image
      essential    = true
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment  = [{ name = "AWS_REGION", value = var.aws_region }]
      dependsOn    = [{ containerName = "tensorzero", condition = "START" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },
    {
      name         = "tensorzero"
      image        = var.tensorzero_image
      essential    = true
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      secrets = [
        { name = "GOOGLE_AI_STUDIO_API_KEY", valueFrom = "${aws_secretsmanager_secret.config.arn}:GOOGLE_AI_STUDIO_API_KEY::" },
        { name = "GROQ_API_KEY", valueFrom = "${aws_secretsmanager_secret.config.arn}:GROQ_API_KEY::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.tensorzero.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "pyrit" {
  family                   = "${var.project}-pyrit"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name         = "pyrit"
    image        = var.pyrit_image
    essential    = true
    portMappings = [{ containerPort = 8001, protocol = "tcp" }]
    environment = [
      { name = "TARGET_URL", value = "http://${aws_lb.main.dns_name}" },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pyrit.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

# ─── Services ────────────────────────────────────────────────────────────────

# Note: tasks run in the public subnets with public IPs, not the private ones.
resource "aws_ecs_service" "app" {
  name            = "${var.project}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.app_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8000
  }

  lifecycle {
    ignore_changes = [desired_count] # auto-scaling manages this
  }
}

resource "aws_ecs_service" "pyrit" {
  name            = "${var.project}-pyrit"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.pyrit.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.pyrit.arn
    container_name   = "pyrit"
    container_port   = 8001
  }
}

# ─── Auto-scaling ────────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "app" {
  max_capacity       = var.app_max_capacity
  min_capacity       = var.app_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "app_cpu" {
  name               = "${var.project}-app-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_scale_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
