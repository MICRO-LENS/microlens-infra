variable "name_prefix" {
  type        = string
  description = "Prefix for naming AWS resources"
  default     = "microlens"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones to use"
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for public subnets, in the same order as azs"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private subnets, in the same order as azs"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "bastion_security_group_id" {
  type        = string
  description = "Security group ID for bastion (NAT instance)"
  default     = ""
}
