# MicroLens Infra Workflow

단계별 진행 상황과 작업 순서를 기록합니다.
완료된 단계는 ✅, 진행 중은 🔄, 대기 중은 ⏳로 표시합니다.

---

## ✅ 1단계: AWS 계정 및 자격 증명 설정

```bash
aws configure
# Access Key ID, Secret Access Key
# Default region: ap-northeast-2
# Default output: json
```

---

## ✅ 2단계: Terraform 기초 리소스 (auth / backend / provider)

- `terraform/provider.tf`: AWS, TLS, Local 프로바이더 설정
- `terraform/auth.tf`: IAM 그룹(`microlens-group`), 사용자(`jina`), SSH 키 페어 자동 생성 → `microlens-key.pem` 로컬 저장
- `terraform/backend.tf`: S3 버킷(`microlens-terraform-state`), DynamoDB 테이블 생성

```bash
# backend.tf의 terraform 블록 주석 처리 상태에서 로컬 백엔드로 시작
cd terraform
terraform init
terraform apply
```

---

## ✅ 2.5단계: S3 백엔드 마이그레이션

```bash
# backend.tf의 terraform 블록 주석 해제 후
cd terraform
terraform init -migrate-state
```

---

## ✅ 3단계: Terraform 모듈 구성

4개 모듈 작성 완료:

| 모듈 | 생성 리소스 |
|------|------------|
| `vpc` | VPC, 퍼블릭·프라이빗 서브넷 각 2개, NAT 인스턴스(t3.nano), EIP, 라우팅 테이블 |
| `ec2` | Control Plane(t3.medium), Worker Nodes(변수), Jenkins(t3.medium), IAM 인스턴스 프로파일 |
| `ecr` | stain-detection-api, stain-classification-api, teeth-api 리포지토리 |
| `s3` | 모델 가중치 버킷(버전 관리 활성화) |
| `ecr` | stain-detection-api, stain-classification-api, teeth-api 리포지토리 |

**IAM 인스턴스 프로파일:**
- `microlens-node-role`: Control Plane + Worker → ECR ReadOnly + S3 ReadOnly
- `microlens-jenkins-role`: Jenkins → ECR PowerUser + S3 ReadOnly

**Worker 노드 변수 (main.tf):**
```hcl
worker_instance_type = "t3.medium"   # g4dn.xlarge로 변경
worker_count         = 2            
```

```bash
terraform apply   # NAT, Control Plane, Jenkins 생성 (Worker는 count=0)
terraform output  # jenkins_public_ip 확인 → Ansible inventory에 기입
```

---

## 🔄 4단계: g4dn vCPU 쿼타 승인 대기 + t3.medium 검증

AWS Service Quotas에서 `Running On-Demand G and VT instances` 8 vCPU 요청 중.

### 대기 기간 동안: t3.medium으로 파이프라인 검증

**목표**: 인프라 구조와 배포 파이프라인의 환경 독립성 확인
**AI 서비스 실행은 g4dn 승인 후에만 수행** (onnxruntime-gpu → CUDA 의존)

#### 4-1. Ansible 인벤토리 설정

`ansible/inventory/hosts.ini`에 `terraform output`으로 확인한 IP 입력:
- `[bastion]`: NAT 인스턴스 퍼블릭 IP
- `[masters]`: Control Plane 프라이빗 IP (AWS 콘솔 확인)

#### 4-2. t3.medium 워커 노드 생성

```hcl
# main.tf
worker_instance_type = "t3.medium"
worker_count         = 2
```

```bash
terraform apply
```

#### 4-3. Ansible 클러스터 구성 (gpu_enabled: false)

```bash
# ansible/group_vars/all.yml
# gpu_enabled: false  ← 이미 기본값

ansible-playbook ansible/site.yml
```

| 플레이북 | 작업 |
|----------|------|
| `01-common.yml` | containerd(SystemdCgroup), kubelet/kubeadm/kubectl 설치 및 버전 고정 |
| `02-gpu.yml` | **스킵** (gpu_enabled: false) |
| `03-master.yml` | kubeadm init, Calico CNI, root/ubuntu kubeconfig 설정, join 커맨드 저장 |
| `04-worker.yml` | kubeadm join |
| `05-addons.yml` | Metrics Server, Nginx Ingress Controller 설치 |

#### 4-4. 검증 항목

```bash
# 클러스터 노드 확인
kubectl get nodes

# Calico Pod 통신 확인
kubectl get pods -n kube-system -l k8s-app=calico-node

# CPU 서비스만 배포하여 Ingress 라우팅 검증
make deploy-cpu

# /stain/classify 경로 확인
curl http://<Control-Plane-IP>/stain/classify/health
```

---

## ⏳ 5단계: g4dn 전환 (쿼타 승인 후)

승인 메일 수신 후 10분 내 전체 GPU 클러스터 가동:

```bash
# 1. main.tf 수정
#    worker_instance_type = "g4dn.xlarge"
#    worker_count         = 2
terraform apply   # 기존 t3.medium 워커 → g4dn.xlarge로 교체

# 2. group_vars/all.yml: gpu_enabled: true
ansible-playbook ansible/site.yml --tags gpu,addons
# 02-gpu.yml: NVIDIA Driver 설치 → 재부팅 → Container Toolkit → containerd 재설정
# 05-addons.yml: nvidia-device-plugin DaemonSet 배포 + GPU 노드 Taint 적용

# 3. GPU 서비스 전체 배포
make deploy-gpu
```

**GPU 노드 검증:**
```bash
# Taint 확인
kubectl describe node <worker> | grep Taint

# GPU 자원 인식 확인
kubectl get node <worker> -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'

# GPU Pod 배포 확인
kubectl get pods -n microlens
```

---

## ⏳ 6단계: Jenkins CI/CD 파이프라인 구축

Jenkins 서버: `http://<jenkins_public_ip>:8080`

```
GitHub Push
  → Webhook (port 8080) → Jenkins
    → docker build
    → docker push → ECR
    → kubectl set image → K8s Rolling Update
```

**GitHub Webhook 설정:**
- GitHub 리포지토리 → Settings → Webhooks
- Payload URL: `http://<jenkins_public_ip>:8080/github-webhook/`
- Content type: `application/json`

**보안 그룹 IP 제한 (선택):**
```hcl
# main.tf
jenkins_webhook_allowed_cidrs = ["140.82.112.0/20", "185.199.108.0/22"]
```

---

## 참고: 전체 진행 타임라인

```
✅ AWS 계정 + 자격 증명
✅ Terraform auth/backend/provider apply
✅ Terraform 모듈(vpc/ec2/s3/ecr) 작성
✅ S3 백엔드 마이그레이션
✅ NAT + Control Plane + Jenkins terraform apply
🔄 g4dn vCPU 쿼타 승인 대기
      └─ t3.medium으로 Ansible + K8s 파이프라인 검증 병행
⏳ g4dn 승인 → worker_count=2, type=g4dn.xlarge → terraform apply
⏳ Ansible gpu 플레이북 → GPU 클러스터 완성
⏳ Jenkins CI/CD 연결
```

---

> **주의**: `*.pem`, `*.tfstate`, `microlens-key.pem` 은 절대 커밋하지 마세요.
