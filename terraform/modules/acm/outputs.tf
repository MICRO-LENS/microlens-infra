output "certificate_arn" {
  value       = aws_acm_certificate_validation.this.certificate_arn
  description = "검증 완료된 ACM 인증서 ARN. ALB HTTPS 리스너에 연결한다."
}
