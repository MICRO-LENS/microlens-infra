module "vpc" {
  source      = "./modules/vpc"
  name_prefix = "microlens"
}

module "s3" {
  source            = "./modules/s3"
  name_prefix       = "microlens"
  model_bucket_name = "microlens-model-weights"
}

module "ecr" {
  source      = "./modules/ecr"
  name_prefix = "microlens"
  repositories = [
    "stain-detection-api",
    "stain-classification-api",
    "teeth-api",
  ]
}

module "ec2" {
  source                    = "./modules/ec2"
  name_prefix               = "microlens"
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  public_subnet_ids         = module.vpc.public_subnet_ids
  key_name                  = aws_key_pair.microlens.key_name
  bastion_security_group_id = module.vpc.nat_security_group_id

  # Jenkins CI/CD – 필요 시 값을 재정의하세요
  # jenkins_port                  = 8080
  # jenkins_webhook_allowed_cidrs = ["140.82.112.0/20", "185.199.108.0/22"]

  # 검증 단계: t3.medium × 2 / g4dn 쿼타 승인 후: worker_instance_type = "g4dn.xlarge"
  worker_instance_type = "t3.medium"
  worker_count         = 2  # g4dn 쿼타 승인 후 worker_instance_type = "g4dn.xlarge" 로 변경
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "control_plane_ids" {
  value = module.ec2.control_plane_instance_ids
}

output "worker_ids" {
  value = module.ec2.worker_instance_ids
}
