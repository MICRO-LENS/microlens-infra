variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "ALB를 배치할 퍼블릭 서브넷 ID 목록 (Multi-AZ를 위해 2개 이상)"
}

variable "certificate_arn" {
  type        = string
  description = "HTTPS 리스너에 적용할 ACM 인증서 ARN"
}

variable "zone_id" {
  type        = string
  description = "Route 53 Hosted Zone ID"
}

variable "domain" {
  type        = string
  description = "A 레코드를 생성할 도메인 (e.g. microlens.cloud)"
}

variable "worker_instance_ids" {
  type        = list(string)
  description = "Target Group에 등록할 K8s 워커 노드 인스턴스 ID 목록 (GPU + CPU)"
}

variable "nginx_nodeport" {
  type        = number
  default     = 30080
  description = "Nginx Ingress Controller HTTP NodePort (05-addons.yml에서 30080으로 고정)"
}

variable "nodes_security_group_id" {
  type        = string
  description = "K8s 노드 Security Group ID. ALB → NodePort 인그레스 규칙 추가에 사용."
}
