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
  │  │  CPU Worker (t3.large) ← 시스템 Pod 전용     │   │
  │  │  ┌──────────────────────────────────────┐   │   │
  │  │  │  ingress-nginx / metrics-server      │   │   │
  │  │  │  stain-classification (CPU)          │   │   │
  │  │  └──────────────────────────────────────┘   │   │
  │  │                                              │   │
  │  │  GPU Worker × 2 (g4dn.xlarge / T4)           │   │
  │  │  Taint: dedicated=gpu:NoSchedule             │   │
  │  │  ┌──────────────────────────────────────┐   │   │
  │  │  │  stain-detection  (GPU)              │   │   │
  │  │  │  teeth            (GPU)              │   │   │
  │  │  └──────────────────────────────────────┘   │   │
  │  │                                              │   │
  │  │  Nginx Ingress                               │   │
  │  │  /stain/detect   → stain-detection           │   │
  │  │  /stain/classify → stain-classification      │   │
  │  │  /teeth/check    → teeth                     │   │
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
│       ├── ec2/          # Control Plane, GPU Worker, CPU Worker, Jenkins, IAM
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
│       ├── 00-nat.yml                 # NAT ip_forward + iptables MASQUERADE 설정
│       ├── 01-common.yml              # containerd + kubelet/kubeadm/kubectl + 버전 고정
│       ├── 02-gpu.yml                 # NVIDIA Driver + Container Toolkit (gpu_workers만)
│       ├── 03-master.yml              # kubeadm init + Calico CNI + kubeconfig
│       ├── 04-worker.yml              # kubeadm join (gpu_workers + cpu_workers)
│       └── 05-addons.yml             # Metrics Server + Nginx Ingress + nvidia-device-plugin
│                                      # GPU 노드 Taint + 라벨링, CPU 노드 라벨링
│
└── k8s/
    ├── 00-namespace.yaml              # microlens 네임스페이스
    ├── 00-serviceaccount.yaml         # S3/ECR 접근용 ServiceAccount
    ├── 01-stain-detection.yaml        # Deployment + Service (GPU, nodeSelector+Toleration)
    ├── 02-stain-classification.yaml   # Deployment + Service (CPU, nodeSelector: node-type=cpu)
    ├── 03-teeth.yaml                  # Deployment + Service (GPU, nodeSelector+Toleration)
    ├── 04-ingress.yaml                # Nginx Ingress L7 경로 라우팅
    └── 05-hpa.yaml                    # HPA × 3 (CPU 70%, max 5 replicas)
```

---

## AMI 선택: Ubuntu 22.04 (Amazon Linux 2 대신)

모든 인스턴스의 AMI로 **Ubuntu 22.04 LTS (Canonical)** 를 사용합니다.

초기 설계에서는 AWS 기본 이미지인 Amazon Linux 2를 사용했으나, 이 아키텍처의 핵심인 **GPU(g4dn.xlarge / NVIDIA T4)** 환경에서 Ubuntu가 명확히 유리하여 전환했습니다.

| 항목 | Amazon Linux 2 | Ubuntu 22.04 |
|------|---------------|----|
| NVIDIA 드라이버 설치 | CUDA rhel7 repo 수동 구성 + DKMS 빌드 | `ubuntu-drivers autoinstall` 한 줄 |
| CUDA 저장소 유지보수 | rhel7 기반, 업데이트 느림 | Ubuntu 전용 공식 repo, 활발히 유지 |
| K8s 공식 문서 기준 | rpm/yum 예시 드묾 | 거의 모든 공식 문서가 Ubuntu 기준 |
| 패키지 버전 고정 | `yum-plugin-versionlock` 별도 설치 | `apt-mark hold` 기본 내장 |
| 트러블슈팅 자료 | 커뮤니티 자료 제한적 | GPU + K8s 조합 자료 압도적으로 풍부 |

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
| CPU Worker × 1 | t3.large | 프라이빗 | ECR ReadOnly, S3 ReadOnly |
| GPU Worker × 2 | g4dn.xlarge | 프라이빗 | ECR ReadOnly, S3 ReadOnly |

---

## 스케줄링 전략

```
GPU Worker (g4dn.xlarge) × 2
  Taint:        dedicated=gpu:NoSchedule  ← Toleration 없는 Pod 진입 차단
  Label:        node-type=gpu
  배치 Pod:     stain-detection, teeth (GPU + Toleration + nodeSelector)

CPU Worker (t3.large) × 1
  Label:        node-type=cpu
  배치 Pod:     stain-classification (nodeSelector: node-type=cpu)
                ingress-nginx, metrics-server (Taint 없어 자연 배치)
```

| 서비스 | 노드 타입 | GPU | nodeSelector | Toleration |
|--------|-----------|-----|--------------|------------|
| stain-detection | GPU Worker | ✅ 1개 | node-type=gpu | dedicated=gpu |
| stain-classification | CPU Worker | ❌ | node-type=cpu | 없음 |
| teeth | GPU Worker | ✅ 1개 | node-type=gpu | dedicated=gpu |
| ingress-nginx | CPU Worker | ❌ | 없음 | 없음 |
| metrics-server | CPU Worker | ❌ | 없음 | 없음 |

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
#    cpu_worker_count     = 1
terraform apply

# 2. group_vars/all.yml: gpu_enabled: true
ansible-playbook ansible/site.yml --tags nat,gpu,addons

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
ansible-playbook site.yml --tags nat      # NAT ip_forward + iptables
ansible-playbook site.yml --tags common   # containerd + kubeadm 설치
ansible-playbook site.yml --tags master   # kubeadm init + Calico
ansible-playbook site.yml --tags worker   # kubeadm join
ansible-playbook site.yml --tags addons   # Ingress + Metrics Server + 노드 라벨/Taint

# CPU Worker 신규 추가 시
ansible-playbook site.yml --tags common,worker --limit bastion,cpu_workers
ansible-playbook site.yml --tags addons
```

### K8s 배포

```bash
make deploy-cpu   # Phase 1: GPU 서비스 제외
make deploy-gpu   # Phase 2: 전체 서비스
```

---

## 클러스터 상태 확인
kubectl 은 클러스터 전체를 API Server를 통해 조회하기 때문에, Control Plane 한 곳에서 모든 노드/Pod 상태를 볼 수 있습니다.

### 노드 상태

```bash
# 노드 목록 + 역할/상태
kubectl get nodes -o wide

# 노드별 라벨 확인 (node-type=gpu/cpu)
kubectl get nodes --show-labels

# 노드별 Taint 확인
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,TAINTS:.spec.taints'

# 노드별 CPU/메모리 실시간 사용량 (Metrics Server 필요)
kubectl top nodes
```

### Pod 상태

```bash
# microlens 네임스페이스 전체 Pod 상태
kubectl get pods -n microlens -o wide

# Pod가 어느 노드에 배치됐는지 확인
kubectl get pods -n microlens -o wide --no-headers | \
  awk '{printf "%-40s %s\n", $1, $7}'

# Pod별 CPU/메모리 실시간 사용량
kubectl top pods -n microlens

# 시스템 Pod 상태 (ingress-nginx, metrics-server)
kubectl get pods -n ingress-nginx -o wide
kubectl get pods -n kube-system -o wide
```

### 자원 점유 상세

```bash
# 노드별 Pod 목록과 리소스 requests/limits
kubectl describe nodes | grep -A 20 "Allocated resources"

# 특정 Pod 상세 (스케줄링 이유, 이벤트 포함)
kubectl describe pod -n microlens <pod-name>

# GPU 할당 현황 (nvidia.com/gpu 기준)
kubectl get nodes -o json | \
  jq '.items[] | {name: .metadata.name, gpu_allocatable: .status.allocatable["nvidia.com/gpu"], gpu_capacity: .status.capacity["nvidia.com/gpu"]}'

# HPA 상태 (현재 replica 수, CPU 사용률)
kubectl get hpa -n microlens
```

### 로그 확인

```bash
# 특정 서비스 로그
kubectl logs -n microlens -l app=stain-detection --tail=50
kubectl logs -n microlens -l app=stain-classification --tail=50
kubectl logs -n microlens -l app=teeth --tail=50

# 이전 컨테이너 로그 (CrashLoopBackOff 디버깅)
kubectl logs -n microlens <pod-name> --previous
```

### NAT 인스턴스 확인

```bash
# NAT 인스턴스에서 실행
sudo systemctl status nat-setup          # NAT 서비스 상태
cat /proc/sys/net/ipv4/ip_forward        # 1이어야 함
sudo iptables -t nat -L POSTROUTING -n -v  # MASQUERADE 규칙 확인
```

> **주의**: `*.pem`, `*.tfvars`, `*.tfstate`, `microlens-key.pem` 은 절대 커밋하지 않습니다.

---

## 관련 저장소

- [microlens-ai-api](../microlens-ai-api) — FastAPI 백엔드 서버
- [microlens-android](../microlens-android) — Android 클라이언트 앱
