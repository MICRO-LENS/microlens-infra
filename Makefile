ANSIBLE    = ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
NAMESPACE  = microlens

.PHONY: deploy-cpu deploy-gpu teardown

## t3.medium 검증 단계: CPU 서비스만 배포 (Namespace, ServiceAccount, stain-classification, Ingress, HPA)
## k8s/*.yaml의 Jinja2 변수(aws_account_id, nat_ip)를 Ansible이 자동 주입
deploy-cpu:
	gpu_enabled=false $(ANSIBLE) --tags k8s-deploy -e "gpu_enabled=false"

## g4dn 쿼타 승인 후: GPU 서비스 포함 전체 배포 (stain-detection, teeth 추가)
## group_vars/all.yml 의 gpu_enabled: true 로 변경 후 실행
deploy-gpu:
	$(ANSIBLE) --tags k8s-deploy -e "gpu_enabled=true"

## 전체 K8s 리소스 삭제 (네임스페이스 삭제 → 모든 하위 리소스 일괄 제거)
teardown:
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
