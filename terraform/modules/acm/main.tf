# microlens.cloud + *.microlens.cloud 와일드카드 인증서
# DNS 검증 방식: Route 53에 CNAME 레코드를 자동 생성하여 검증
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  # 인증서 교체 시 새 인증서를 먼저 만들고 기존 것을 삭제 (다운타임 방지)
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.name_prefix}-cert"
  }
}

# ACM이 요구하는 DNS 검증 레코드를 Route 53에 자동 생성
# domain_name + *.domain_name 두 개의 검증 옵션이 나오지만
# 실제로 CNAME 값이 동일하므로 for_each로 중복 제거 후 하나만 생성된다
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # allow_overwrite: 이미 레코드가 있어도 오류 없이 진행 (재실행 안전성)
  allow_overwrite = true
}

# DNS 레코드가 전파되고 ACM 검증이 완료될 때까지 대기
# 이 리소스를 참조하는 ALB 리스너는 인증서가 ISSUED 상태일 때만 생성된다
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
