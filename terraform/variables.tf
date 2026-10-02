# ─── Core ────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix applied to every resource"
  type        = string
  default     = "research-agent"
}

# ─── Container images ────────────────────────────────────────────────────────

# Empty = use the repo's :latest tag, which CI pushes on every deploy.
# CI pins running services to an exact git-SHA tag; these only seed Terraform's revision.
variable "app_image" {
  description = "Image URI override for the main app (default: ECR :latest)"
  type        = string
  default     = ""
}

variable "pyrit_image" {
  description = "Image URI override for the PyRIT dashboard (default: ECR :latest)"
  type        = string
  default     = ""
}

variable "tensorzero_image" {
  description = "Image URI override for the TensorZero sidecar (default: ECR :latest)"
  type        = string
  default     = ""
}

# ─── Auth ────────────────────────────────────────────────────────────────────

variable "api_key" {
  description = "API key for authenticating requests to the research agent"
  type        = string
  sensitive   = true
  default     = ""
}

# ─── App sizing and scaling ──────────────────────────────────────────────────

variable "app_desired_count" {
  description = "Initial number of app ECS tasks"
  type        = number
  default     = 1
}

variable "app_min_capacity" {
  description = "Minimum number of app ECS tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "app_max_capacity" {
  description = "Maximum number of app ECS tasks for auto-scaling"
  type        = number
  default     = 5
}

# Sized from measured usage, not guesses. Over 24h at 2 vCPU / 4 GB the task peaked at
# 235 CPU units and sat flat at ~600 MB. CPU is cut hardest: running short only slows a
# job. Memory keeps ~3x headroom: running short gets the task killed (OOM).
variable "app_cpu" {
  description = "CPU units for app task (1024 = 1 vCPU)"
  type        = string
  default     = "512"
}

variable "app_memory" {
  description = "Memory in MB for app task"
  type        = string
  default     = "2048"
}

variable "cpu_scale_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

# ─── Data layer ──────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_multi_az" {
  description = "Enable RDS Multi-AZ for high availability"
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis cache nodes"
  type        = number
  default     = 1
}

# ─── Observability and TLS ───────────────────────────────────────────────────

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS. Leave empty to use HTTP only."
  type        = string
  default     = ""
}
