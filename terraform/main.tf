# Core infrastructure: the VPC everything else is built on top of.
# Peripheral concerns live in their own files (security.tf, data.tf, ecs.tf, ...).

# ─── Data sources & locals ───────────────────────────────────────────────────

data "aws_availability_zones" "available" {}

locals {
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  https_enabled = var.acm_certificate_arn != ""
}

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project}-vpc" }
}

# ─── Subnets ─────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project}-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.project}-private-${count.index}" }
}

# ─── Routing ─────────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# No internet route. Only RDS and Redis live here, and they never call out.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── VPC Endpoints ───────────────────────────────────────────────────────────
# ECS tasks run in public subnets with public IPs, so they reach ECR, Secrets Manager,
# Bedrock and CloudWatch through the internet gateway for free (traffic is still TLS).
# Interface endpoints for those services cost $0.01/hr per AZ each (~$73/mo for 5 x 2 AZs)
# and only pay off once tasks move to private subnets.
# ponytail: re-add interface endpoints if tasks move to private subnets (or add a NAT, ~$33/mo).

# Gateway endpoints are free, so keep S3 (ECR image layers are served from S3).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
}
