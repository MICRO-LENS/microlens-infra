terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  # 자격 증명은 환경 변수나 ~/.aws/credentials 파일에서 자동으로 참조됩니다.
}

provider "tls" {
  # TLS 프로바이더 버전은 required_providers에서 지정됨
}

provider "local" {
  # Local 프로바이더 버전은 required_providers에서 지정됨
}