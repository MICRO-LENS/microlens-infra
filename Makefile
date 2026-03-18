NAMESPACE  = microlens

.PHONY: teardown

## 전체 K8s 리소스 삭제 (네임스페이스 삭제 → 모든 하위 리소스 일괄 제거)
teardown:
	kubectl delete namespace $(NAMESPACE) --ignore-not-found
