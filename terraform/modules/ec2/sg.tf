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
