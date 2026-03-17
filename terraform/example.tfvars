# Example Terraform Variables for MicroLens Infra
# Copy this file to terraform.tfvars and customize the values

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
azs = ["ap-northeast-2a", "ap-northeast-2c"]
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]

# EC2 Configuration
worker_instance_type = "g4dn.xlarge"
worker_count = 2

# Security
admin_ssh_cidrs = ["0.0.0.0/0"]  # Restrict in production