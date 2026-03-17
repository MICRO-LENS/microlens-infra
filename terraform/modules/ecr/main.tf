resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name = each.key

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.name_prefix}-ecr-${each.key}"
  }
}
