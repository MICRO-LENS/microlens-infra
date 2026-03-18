# ============================================================
# AMI
# ============================================================

locals {
  ami = data.aws_ami.ubuntu.id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ============================================================
# EC2 – Control Plane
# ============================================================

resource "aws_instance" "control_plane" {
  count                  = 1
  ami                    = local.ami
  instance_type          = "t3.medium"
  subnet_id              = var.private_subnet_ids[0]
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
  }

  tags = {
    Name = "${var.name_prefix}-control-plane"
    Role = "control-plane"
  }
}

# ============================================================
# EC2 – Worker Nodes
# var.worker_instance_type: t3.medium(검증) → g4dn.xlarge(GPU)
# var.worker_count:         0(쿼타 대기) → 2(승인 후)
# ============================================================

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = local.ami
  instance_type          = var.worker_instance_type
  subnet_id              = element(var.private_subnet_ids, 1)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
  }

  tags = {
    Name = "${var.name_prefix}-worker-${count.index + 1}"
    Role = "worker"
  }
}

# ============================================================
# EC2 – Jenkins Server
# 퍼블릭 서브넷에 배치하여 GitHub Webhook을 직접 수신합니다.
# t3.medium (2 vCPU / 4 GB): K8s Control Plane과 분리하여
# Jenkins 빌드 부하가 클러스터에 영향을 주지 않도록 합니다.
# ============================================================

resource "aws_instance" "jenkins" {
  ami                         = local.ami
  instance_type               = "t3.medium"
  subnet_id                   = var.public_subnet_ids[0]
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    # Jenkins 워크스페이스, 빌드 아티팩트, Docker 이미지 캐시 고려
    volume_size = 50
  }

  tags = {
    Name = "${var.name_prefix}-jenkins"
    Role = "cicd"
  }
}

resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-jenkins-eip"
  }
}
