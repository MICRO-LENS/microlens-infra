variable "name_prefix" {
  type        = string
  description = "Prefix for naming resources"
  default     = "microlens"
}

variable "ecr_repositories" {
  type        = list(string)
  description = "List of ECR repository names"
  default     = ["stain-detection-api", "stain-classification-api", "teeth-api"]
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 bucket for AI model weights"
  default     = "microlens-ai-models"
}