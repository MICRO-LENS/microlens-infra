# ============================================================
# ALB Security Group
# 인터넷 트래픽(80, 443)만 허용
# ============================================================
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow HTTP/HTTPS inbound to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-alb-sg"
  }
}

# ============================================================
# Application Load Balancer
# 퍼블릭 서브넷 2개에 걸쳐 배포 (Multi-AZ)
# ============================================================
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.name_prefix}-alb"
  }
}

# ============================================================
# Target Group → K8s 워커 노드의 Nginx Ingress NodePort(30080)
#
# target_type = instance: 인스턴스 ID로 등록
# health_check matcher 200-404:
#   Nginx Ingress는 매칭 규칙 없는 경로에 404를 반환하므로
#   404도 정상 응답으로 인정해야 헬스 체크가 통과된다
# ============================================================
resource "aws_lb_target_group" "this" {
  name     = "${var.name_prefix}-tg"
  port     = var.nginx_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    port                = tostring(var.nginx_nodeport)
    protocol            = "HTTP"
    matcher             = "200-404"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = {
    Name = "${var.name_prefix}-tg"
  }
}

# ============================================================
# HTTP 리스너: 80 → 443 영구 리다이렉트
# ============================================================
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ============================================================
# HTTPS 리스너: ACM 인증서 적용 후 Target Group으로 포워딩
# ELBSecurityPolicy-TLS13-1-2-2021-06: TLS 1.2/1.3 권장 정책
# ============================================================
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ============================================================
# Target Group에 GPU 워커 + CPU 워커 전체 등록
# K8s NodePort 특성상 어느 노드로 트래픽이 와도
# kube-proxy가 실제 Pod가 있는 노드로 전달한다
#
# count 사용 이유:
#   for_each + toset()은 plan 시점에 키가 확정되어야 하는데
#   EC2 인스턴스 ID는 apply 전까지 알 수 없어 오류가 발생한다.
#   count는 길이(정수)만 plan 시점에 알면 되므로 이 제약을 우회한다.
# ============================================================
resource "aws_lb_target_group_attachment" "workers" {
  count = length(var.worker_instance_ids)

  target_group_arn = aws_lb_target_group.this.arn
  target_id        = var.worker_instance_ids[count.index]
  port             = var.nginx_nodeport
}

# ============================================================
# Route 53 A Alias 레코드: microlens.cloud → ALB
# ============================================================
resource "aws_route53_record" "apex" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
