variable "name_prefix" {
  type        = string
  description = "Prefix for naming resources"
  default     = "microlens"
}

variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create"
  default     = ["stain-detection-api", "stain-classification-api", "teeth-api"]
}
