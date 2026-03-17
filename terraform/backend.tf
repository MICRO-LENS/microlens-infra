terraform {
   backend "s3" {
     bucket         = "microlens-terraform-state-jina"
     key            = "terraform.tfstate"
     region         = "ap-northeast-2"
     dynamodb_table = "microlens-terraform-locks"
     use_lockfile   = true
   }
 }

# S3 버킷 생성 (Terraform State 저장용)
resource "aws_s3_bucket" "terraform_state" {
  bucket = "microlens-terraform-state-jina" # 전역 유일 이름으로 수정 필요
  
  lifecycle {
    prevent_destroy = true # 실수로 삭제되는 것 방지
  }
}

# S3 버전 관리 활성화 (파일 복구용)
resource "aws_s3_bucket_versioning" "enabled" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DynamoDB 테이블 생성 (State Locking용)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "microlens-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}