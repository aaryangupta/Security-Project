output "alb_dns" {
  description = "Public DNS name of the application load balancer"
  value       = aws_lb.main.dns_name
}

output "app_ecr_url" {
  description = "ECR repository URL for the app image"
  value       = aws_ecr_repository.app.repository_url
}

output "pyrit_ecr_url" {
  description = "ECR repository URL for the PyRIT dashboard image"
  value       = aws_ecr_repository.pyrit.repository_url
}

output "tensorzero_ecr_url" {
  description = "ECR repository URL for the TensorZero gateway image"
  value       = aws_ecr_repository.tensorzero.repository_url
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "db_endpoint" {
  description = "RDS PostgreSQL connection endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}
