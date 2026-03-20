output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALB DNS 이름 (Route 53 A 레코드 alias 대상)"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "ALB Security Group ID. 노드 SG 인그레스 규칙에서 source로 참조."
}
