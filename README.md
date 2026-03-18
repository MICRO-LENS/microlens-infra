# microlens-infra

MicroLens 프로젝트의 인프라스트럭처 전용 저장소입니다.
Terraform으로 AWS 리소스를 프로비저닝하고, Ansible로 서버를 구성하며, Kubernetes 매니페스트로 AI 서비스를 배포합니다.

---

## 아키텍처 개요

```
  [ Android Client ]
         │ HTTPS
         ▼
  ┌──────────────────────────────────────────────────────┐
  │                     AWS Cloud                        │
  │                                                      │
  │  퍼블릭 서브넷                                        │
  │  ┌─────────────────────┐  ┌─────────────────────┐   │
  │  │  Bastion / NAT      │  │  Jenkins (t3.medium) │   │
  │  │  (t3.nano)          │  │  :8080               │   │
  │  │  SSH 진입점         │  │  GitHub Webhook 수신  │   │
  │  │  프라이빗 트래픽    │  │  ECR Push            │   │
  │  │  라우팅             │  └──────────┬──────────┘   │
  │  └────────┬────────────┘             │ docker push  │
  │           │ SSH ProxyJump            ▼              │
  │           │              ECR (3개 리포지토리)         │
  │  프라이빗 서브넷                                      │
  │  ┌──────────────────────────────────────────────┐   │
  │  │  Kubernetes Cluster                          │   │
  │  │                                              │   │
  │  │  Control Plane (t3.medium)                   │   │
  │  │                                              │   │
  │  │  Worker Node × 2 (g4dn.xlarge / T4 GPU)     │   │
  │  │  ┌──────────────────────────────────────┐   │   │
  │  │  │  Nginx Ingress Controller            │   │   │
  │  │  │  /stain/detect   → stain-detection   │   │   │
  │  │  │  /stain/classify → stain-classif..   │   │   │
  │  │  │  /teeth/check    → teeth             │   │   │
  │  │  └──────────────────────────────────────┘   │   │
  │  └──────────────────────────────────────────────┘   │
  │                                                      │
  │  S3: microlens-model-weights (모델 가중치)            │
  └──────────────────────────────────────────────────────┘
```

---

## 디렉토리 구조

```
microlens-infra/
├── main.tf               # 모듈 orchestration (vpc, ec2, s3, ecr)
├── auth.tf               # IAM 그룹/사용자, SSH 키 페어
├── backend.tf            # S3 원격 백엔드 + DynamoDB 락
├── provider.tf           # AWS / TLS / Local 프로바이더
├── outputs.tf            # 주요 리소스 출력값
├── Makefile              # K8s 단계별 배포 명령
├── workflow.md           # 단계별 작업 흐름 가이드
│
├── terraform/
│   └── modules/
│       ├── vpc/          # VPC, 퍼블릭·프라이빗 서브넷(각 2개), NAT 인스턴스, EIP
│       ├── ec2/          # Control Plane, Worker Nodes, Jenkins, IAM 인스턴스 프로파일
│       ├── s3/           # 모델 가중치 저장 버킷 (버전 관리 활성화)
│       └── ecr/          # 컨테이너 이미지 레지스트리 (repositories 변수로 관리)
│
├── ansible/
│   ├── ansible.cfg                    # 기본 설정 (키 경로, ProxyJump)
│   ├── site.yml                       # 전체 실행 진입점
│   ├── inventory/
│   │   └── hosts.ini                  # 호스트 목록 (terraform output으로 IP 채우기)
│   ├── group_vars/
│   │   ├── all.yml                    # 공통 변수 (gpu_enabled, k8s_version)
│   │   └── k8s.yml                    # Bastion ProxyJump SSH 설정
│   └── playbooks/
│       ├── 01-common.yml              # containerd + kubelet/kubeadm/kubectl + 버전 고정
│       ├── 02-gpu.yml                 # NVIDIA Driver + Container Toolkit (gpu_enabled 시)
│       ├── 03-master.yml              # kubeadm init + Calico CNI + kubeconfig
│       ├── 04-worker.yml              # kubeadm join
│       └── 05-addons.yml             # Metrics Server + Nginx Ingress + nvidia-device-plugin
│
└── k8s/
    ├── 00-namespace.yaml              # microlens 네임스페이스
    ├── 00-serviceaccount.yaml         # S3/ECR 접근용 ServiceAccount
    ├── 01-stain-detection.yaml        # Deployment + Service (GPU, dedicated=gpu Toleration)
    ├── 02-stain-classification.yaml   # Deployment + Service (CPU only)
    ├── 03-teeth.yaml                  # Deployment + Service (GPU, dedicated=gpu Toleration)
    ├── 04-ingress.yaml                # Nginx Ingress L7 경로 라우팅
    └── 05-hpa.yaml                    # HPA × 3 (CPU 70%, max 5 replicas)
```

---

## AMI 선택: Ubuntu 22.04 (Amazon Linux 2 대신)

모든 인스턴스의 AMI로 **Ubuntu 22.04 LTS (Canonical)** 를 사용합니다.

초기 설계에서는 AWS 기본 이미지인 Amazon Linux 2를 사용했으나, 이 아키텍처의 핵심인 **GPU(g4dn.xlarge / NVIDIA T4)** 환경에서 Ubuntu가 명확히 유리하여 전환했습니다.

| 항목 | Amazon Linux 2 | Ubuntu 22.04 |
|------|---------------|--------------|
| NVIDIA 드라이버 설치 | CUDA rhel7 repo 수동 구성 + DKMS 빌드 | `ubuntu-drivers autoinstall` 한 줄 |
| CUDA 저장소 유지보수 | rhel7 기반, 업데이트 느림 | Ubuntu 전용 공식 repo, 활발히 유지 |
| K8s 공식 문서 기준 | rpm/yum 예시 드묾 | 거의 모든 공식 문서가 Ubuntu 기준 |
| 패키지 버전 고정 | `yum-plugin-versionlock` 별도 설치 | `apt-mark hold` 기본 내장 |
| 트러블슈팅 자료 | 커뮤니티 자료 제한적 | GPU + K8s 조합 자료 압도적으로 풍부 |

```hcl
# terraform/modules/ec2/main.tf, vpc/main.tf
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| 클라우드 | AWS (EC2, ECR, S3, VPC) |
| IaC | Terraform |
| 서버 구성 | Ansible |
| 컨테이너 오케스트레이션 | Kubernetes (kubeadm) |
| CNI | Calico (Network Policy 지원, AWS 환경 IPIP 모드) |
| CI/CD | Jenkins |

---

## 인스턴스 구성

| 역할 | 타입 | 서브넷 | IAM 권한 |
|------|------|--------|----------|
| Bastion / NAT | t3.nano | 퍼블릭 | - |
| Jenkins | t3.medium | 퍼블릭 | ECR PowerUser, S3 ReadOnly |
| Control Plane | t3.medium | 프라이빗 | ECR ReadOnly, S3 ReadOnly |
| Worker Node × 2 | g4dn.xlarge | 프라이빗 | ECR ReadOnly, S3 ReadOnly |

---

## GPU 자원 관리 전략

```
Worker Node (g4dn.xlarge)
  Taint: dedicated=gpu:NoSchedule
    → 일반 Pod 스케줄링 차단 (Jenkins 빌드 Pod 등)

GPU 서비스 Pod (stain-detection, teeth)
  Toleration: dedicated=gpu:Equal:NoSchedule
  resources.limits: nvidia.com/gpu: 1
    → GPU 노드에만 배치, Pod 단위 GPU 격리
```

---

## 배포 단계 (2-Phase 전략)

### Phase 1 — t3.medium 검증 (g4dn 쿼타 대기 중)

네트워크, Ingress 라우팅, 파이프라인 연결만 검증합니다.

```bash
# group_vars/all.yml: gpu_enabled: false
cd ansible
ansible-playbook site.yml
make deploy-cpu   # stain-classification(CPU)만 배포
```

### Phase 2 — g4dn 전환 (쿼타 승인 후)

```bash
# 1. main.tf 수정
#    worker_instance_type = "g4dn.xlarge"
#    worker_count         = 2
terraform apply

# 2. group_vars/all.yml: gpu_enabled: true
ansible-playbook ansible/site.yml --tags gpu,addons

# 3. GPU 서비스 포함 전체 배포
make deploy-gpu
```

---

## 시작하기

### 사전 요구사항

- Terraform >= 1.5
- AWS CLI (`aws configure` 완료, ap-northeast-2)
- Ansible >= 2.14
- kubectl

### Terraform 실행

```bash
# 1. 초기화 (backend.tf의 terraform 블록 주석 처리 상태에서 시작)
terraform init

# 2. 리소스 생성
terraform apply

# 3. S3 백엔드 활성화 (backend.tf 주석 해제 후)
terraform init -migrate-state

# 4. 출력값 확인 → ansible/inventory/hosts.ini IP 채우기
terraform output
```

### Ansible 실행

```bash
cd ansible

# inventory/hosts.ini에 terraform output의 IP를 채운 후:
ansible-playbook site.yml

# 단계별 실행
ansible-playbook site.yml --tags common   # containerd + kubeadm 설치
ansible-playbook site.yml --tags master   # kubeadm init + Calico
ansible-playbook site.yml --tags worker   # kubeadm join
ansible-playbook site.yml --tags addons   # Ingress + Metrics Server
```

### K8s 배포

```bash
make deploy-cpu   # Phase 1: GPU 서비스 제외
make deploy-gpu   # Phase 2: 전체 서비스
```

> **주의**: `*.pem`, `*.tfvars`, `*.tfstate`, `microlens-key.pem` 은 절대 커밋하지 않습니다.

---

## 관련 저장소

- [microlens-ai-api](../microlens-ai-api) — FastAPI 백엔드 서버
- [microlens-android](../microlens-android) — Android 클라이언트 앱
