output "bucket_id" {
  value = aws_s3_bucket.model_weights.id
}

output "bucket_arn" {
  value = aws_s3_bucket.model_weights.arn
}
