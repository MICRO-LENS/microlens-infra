variable "name_prefix" {
  type        = string
  description = "Prefix for naming resources"
  default     = "microlens"
}

variable "model_bucket_name" {
  type        = string
  description = "S3 bucket name for model weights (must be globally unique)"
  default     = "microlens-model-weights"
}
