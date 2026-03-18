variable "name_prefix" {
  type        = string
  description = "Prefix for naming resources"
  default     = "microlens"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the nodes will be deployed"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs where K8s nodes will be placed"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs – Jenkins instance is placed here to receive webhooks"
}

variable "key_name" {
  type        = string
  description = "SSH key name to attach to instances"
}

variable "bastion_security_group_id" {
  type        = string
  description = "Security group ID that is allowed to SSH into nodes"
}

variable "jenkins_port" {
  type        = number
  description = "Port Jenkins listens on (web UI and GitHub webhook endpoint)"
  default     = 8080
}

variable "jenkins_webhook_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach Jenkins webhook port. Restrict to GitHub IP ranges in production."
  default     = ["0.0.0.0/0"]
}

variable "worker_instance_type" {
  type        = string
  description = "Worker node instance type. t3.medium for validation, g4dn.xlarge for GPU production."
  default     = "g4dn.xlarge"
}

variable "worker_count" {
  type        = number
  description = "Number of GPU worker nodes. Set 0 while waiting for G-instance vCPU quota approval."
  default     = 2
}

variable "cpu_worker_count" {
  type        = number
  description = "Number of CPU-only worker nodes for system pods and CPU services (stain-classification)."
  default     = 1
}

variable "cpu_worker_instance_type" {
  type        = string
  description = "CPU worker node instance type. t3.large (2 vCPU, 8GiB) covers system pods + stain-classification limits."
  default     = "t3.large"
}
