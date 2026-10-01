# Weekly red team run: Mondays at 02:00 UTC.

resource "aws_cloudwatch_event_rule" "weekly_redteam" {
  name                = "${var.project}-weekly-redteam"
  schedule_expression = "cron(0 2 ? * MON *)"
}

resource "aws_cloudwatch_event_target" "redteam_ecs" {
  rule     = aws_cloudwatch_event_rule.weekly_redteam.name
  arn      = aws_ecs_cluster.main.arn
  role_arn = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.pyrit.arn
    launch_type         = "FARGATE"
    network_configuration {
      subnets          = aws_subnet.public[*].id
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = true
    }
  }
}
