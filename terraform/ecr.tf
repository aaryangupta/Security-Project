resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "pyrit" {
  name                 = "${var.project}-pyrit"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "tensorzero" {
  name                 = "${var.project}-tensorzero"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
}

# Every CI push adds an image (~3.3 GB for the app). Without expiry, storage grows forever.
# Keep the last 3: enough for the CI rollback to the previous revision.
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each = {
    app        = aws_ecr_repository.app.name
    pyrit      = aws_ecr_repository.pyrit.name
    tensorzero = aws_ecr_repository.tensorzero.name
  }
  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 3 most recent images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 3 }
      action       = { type = "expire" }
    }]
  })
}
