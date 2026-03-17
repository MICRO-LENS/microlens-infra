resource "aws_s3_bucket" "model_weights" {
  bucket = var.model_bucket_name

  tags = {
    Name = "${var.name_prefix}-model-weights"
  }
}

resource "aws_s3_bucket_versioning" "model_weights" {
  bucket = aws_s3_bucket.model_weights.id

  versioning_configuration {
    status = "Enabled"
  }
}
