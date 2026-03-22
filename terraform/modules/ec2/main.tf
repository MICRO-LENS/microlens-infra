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
# EC2 – Worker Nodes (inference pair)
# stain-detection × 2 + teeth × 2 를 podAntiAffinity로 분산.
# 노드 1대 장애 시 나머지 노드가 두 서비스 모두 흡수 → HA.
# var.worker_instance_type: t3.xlarge (4 vCPU, 16 GB) – CPU 추론
# var.worker_count:         2 (AntiAffinity 분산 최소 단위)
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
# EC2 – CPU Worker Node
# 시스템 Pod(ingress-nginx, metrics-server)와 CPU 서비스(stain-classification) 전용.
# GPU 노드(g4dn.xlarge)에 Taint를 걸어 GPU Pod 전용으로 확보하고,
# 시스템 Pod와 CPU 서비스는 이 노드에서 실행된다.
# ============================================================

resource "aws_instance" "cpu_worker" {
  count                  = var.cpu_worker_count
  ami                    = local.ami
  instance_type          = var.cpu_worker_instance_type
  subnet_id              = element(var.private_subnet_ids, 1)
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nodes.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  root_block_device {
    volume_type = "gp3"
    # 시스템 Pod 및 CPU 서비스 용도. 모델 가중치 로딩 없으므로 50GB로 충분.
    volume_size = 50
  }

  tags = {
    Name = "${var.name_prefix}-cpu-worker-${count.index + 1}"
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
