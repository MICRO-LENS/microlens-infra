output "iam_user_arn" {
  value = aws_iam_user.jina.arn
}

output "iam_user_name" {
  value = aws_iam_user.jina.name
}

output "access_key_id" {
  value = aws_iam_access_key.jina_key.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.jina_key.secret
  sensitive = true
}

output "ssh_key_fingerprint" {
  value = tls_private_key.microlens_key.public_key_fingerprint_md5
}

output "nat_public_ip" {
  value       = module.vpc.nat_public_ip
  description = "NAT 인스턴스 퍼블릭 IP. Ansible inventory [bastion] ansible_host에 입력하세요."
}

output "jenkins_public_ip" {
  value       = module.ec2.jenkins_public_ip
  description = "Jenkins EIP. GitHub Webhook: http://<ip>:8080/github-webhook/"
}

output "jenkins_instance_id" {
  value = module.ec2.jenkins_instance_id
}

output "route53_name_servers" {
  value       = module.route53.name_servers
  description = "가비아 네임서버 설정에 입력할 NS 레코드 4개"
}

output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "ALB DNS 이름 (디버깅용, 실제 접속은 microlens.cloud 사용)"
}