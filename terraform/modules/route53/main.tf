resource "aws_route53_zone" "this" {
  name = var.domain

  tags = {
    Name = "${var.name_prefix}-zone"
  }
}
