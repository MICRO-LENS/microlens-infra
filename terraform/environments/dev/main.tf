terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

module "vpc" {
  source = "../../modules/vpc"
  bastion_security_group_id = aws_security_group.bastion.id
}

module "ec2" {
  source = "../../modules/ec2"

  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  public_subnet_ids        = module.vpc.public_subnet_ids
  key_name                 = "microlens-key"
  bastion_security_group_id = aws_security_group.bastion.id  # NAT instance의 SG
}

module "ecr" {
  source = "../../modules/ecr"
}

module "s3" {
  source = "../../modules/s3"
}

# Bastion Security Group (NAT instance용)
resource "aws_security_group" "bastion" {
  name        = "microlens-bastion-sg"
  description = "Security group for bastion (NAT instance)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 외부 SSH 허용
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "microlens-bastion-sg"
  }
}

# NAT instance에 SG 할당 (VPC 모듈에서 NAT instance 수정 필요)
# VPC 모듈의 NAT instance에 security_groups 추가