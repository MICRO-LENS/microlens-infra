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
# IAM – K8s Node Role
# EC2 인스턴스 프로파일: Worker/Control Plane 이 ECR에서
# 이미지를 Pull하고 S3에서 모델 가중치를 읽을 수 있도록 허용합니다.
# ============================================================

resource "aws_iam_role" "node" {
  name = "${var.name_prefix}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_s3_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name_prefix}-node-profile"
  role = aws_iam_role.node.name
}

# ============================================================
# IAM – Jenkins Role
# Jenkins는 빌드 후 ECR에 이미지를 Push해야 하므로
# PowerUser 권한 (pull + push + 리포지토리 관리)을 부여합니다.
# ============================================================

resource "aws_iam_role" "jenkins" {
  name = "${var.name_prefix}-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-jenkins-role"
  }
}

resource "aws_iam_role_policy_attachment" "jenkins_ecr_power" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "jenkins_s3_readonly" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name_prefix}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# ============================================================
# Security Group – K8s Nodes (Control Plane + Workers)
# ============================================================

resource "aws_security_group" "nodes" {
  name        = "${var.name_prefix}-nodes-sg"
  description = "Security group for Kubernetes nodes"
  vpc_id      = var.vpc_id

  ingress {
    description = "K8s control plane / node full mesh communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "SSH from bastion/NAT"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-nodes-sg"
  }
}

# ============================================================
# Security Group – Jenkins
# ============================================================

resource "aws_security_group" "jenkins" {
  name        = "${var.name_prefix}-jenkins-sg"
  description = "Security group for Jenkins CI/CD server"
  vpc_id      = var.vpc_id

  # GitHub Webhook 및 Jenkins Web UI
  ingress {
    description = "Jenkins web UI and GitHub webhook (port ${var.jenkins_port})"
    from_port   = var.jenkins_port
    to_port     = var.jenkins_port
    protocol    = "tcp"
    cidr_blocks = var.jenkins_webhook_allowed_cidrs
  }

  # SSH는 Bastion/NAT 경유로만 허용
  ingress {
    description     = "SSH from bastion/NAT"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-jenkins-sg"
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

