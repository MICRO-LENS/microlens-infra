output "control_plane_instance_ids" {
  value = aws_instance.control_plane[*].id
}

output "worker_instance_ids" {
  value = aws_instance.worker[*].id
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "jenkins_public_ip" {
  value       = aws_eip.jenkins.public_ip
  description = "Jenkins EIP. Webhook: http://<this_ip>:<jenkins_port>/github-webhook/"
}

output "node_security_group_id" {
  value = aws_security_group.nodes.id
}

output "jenkins_security_group_id" {
  value = aws_security_group.jenkins.id
}
