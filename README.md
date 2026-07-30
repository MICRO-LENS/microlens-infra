<div align="center">

# 🏗️ MicroLens Infra

### 일상 속 미세한 부분까지, 대신 확인해주는 시력보조 파트너 — 인프라스트럭처

**Terraform으로 AWS를 프로비저닝하고, Ansible로 서버를 구성하며, Kustomize + ArgoCD로 Kubernetes 서비스를 GitOps 배포합니다.**

![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonwebservices&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=flat&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes%20(kubeadm)-326CE5?style=flat&logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-EF7B4D?style=flat&logo=argo&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-D24939?style=flat&logo=jenkins&logoColor=white)

🌐 **서비스**: [microlens.cloud](https://microlens.cloud/) · 📹 **시연 영상**: [YouTube](https://youtu.be/7jnekg9lZeo)

[![MicroLens 시연 영상](https://img.youtube.com/vi/7jnekg9lZeo/0.jpg)](https://youtu.be/7jnekg9lZeo)

</div>

---

## 📌 프로젝트 소개

MicroLens는 **2023 배리어프리 앱 개발 콘테스트 우수상**을 수상한 시각장애인용 옷 얼룩 탐지 앱 [Stainless](https://github.com/catapillar0505/Stainless)를 서버 기반 웹 서비스로 발전시킨 **1인 프로젝트**입니다. 이 저장소는 그 서비스를 받치는 전체 인프라를 코드로 관리합니다.

- **IaC 전 구간 자동화**: EKS 같은 관리형 서비스 대신 **kubeadm으로 클러스터를 직접 구축** — VPC 설계부터 CNI, Ingress, GitOps까지 전 레이어를 직접 다뤘습니다
- **GitOps 운영**: Jenkins가 이미지를 빌드하고 이 저장소의 Kustomize 태그를 갱신하면, ArgoCD가 감지해 자동 배포합니다
- **관측 기반 비용 최적화**: GPU 사용률 2.5%를 직접 측정하고 GPU → CPU 아키텍처로 전환, 절감 비용으로 HA를 확보했습니다 (아래 트러블슈팅 참고)

![MicroLens 시연 — 얼룩 탐지](docs/images/demo-stain-detection.png)

---

## 🔎 트러블슈팅 — GPU 사용률 2.5%를 발견하고 아키텍처를 뒤집다

> 이 프로젝트에서 가장 의미 있었던 의사결정입니다. "GPU가 있으면 좋다"가 아니라, **관측 데이터로 아키텍처를 결정**했습니다.

### 초기 상황

- T4 GPU(g4dn.xlarge)로 학습시킨 YOLOv8 얼룩 분류 모델, YOLOv12 얼룩 탐지 모델을 서빙
- K8s `nvidia.com/gpu: 1` 설정으로 GPU 워커 노드당 GPU Pod 1개만 스케줄링되도록 배포

### 운영 중 문제 발견

- `nvidia-smi`로 추론 API 요청 시 GPU VRAM 점유량 관찰 → 두 노드 모두 **385 MiB / 15,360 MiB = 2.5%**만 사용
- 0.1초 간격 `nvidia-smi` 모니터링으로 요청 시 GPU-util 변화 관찰 → **8% → 11%** 소폭 변화에 그침

### 판단

- 단일 탐지 모델 + ONNX 경량화 조합은 GPU 자원을 크게 활용하지 않음
- NVIDIA 드라이버 스택 관리 부담 + g4dn.xlarge 인스턴스 비용을 지불하기엔 모델이 너무 가볍고, 명백한 비용 낭비

### 개선

| 항목 | 변경 전 | 변경 후 |
|------|---------|---------|
| 인스턴스 | g4dn.xlarge (GPU) | **t3.xlarge (CPU)** — 비용 다운그레이드 |
| 스케줄링 | GPU taints / tolerations | 전략 삭제 → **HA 중심 재설계** |
| 가용성 | GPU 노드당 Pod 1개 | **replicas 2 + podAntiAffinity(required)** |

```
podAntiAffinity: labelSelector app=stain-detection 인 Pod와 같은 노드 배치 금지
  → 노드1: stain-detection-1 + teeth-1
  → 노드2: stain-detection-2 + teeth-2
  → 노드 1대 장애 시 나머지 노드가 두 서비스 모두 흡수
```

### 결과

**비용을 절감하면서 가용성은 오히려 높아진 서버.** GPU가 다시 필요해질 때를 대비해 `gpu_enabled` 플래그 하나로 GPU 아키텍처로 복귀할 수 있도록 Ansible 플레이북(NVIDIA Driver, GPU Time-Slicing)은 유지했습니다.

---

## 🛠️ 운영 기록 (커밋 이력에서)

- **GitOps 전환**: Jinja2 수동 배포 → **Kustomize 매니페스트 구조 전환 + ArgoCD 도입**, 배포 이력이 전부 git 커밋(`ci: update image tags to <sha>`)으로 남는 구조
- **모델 배포 자동화**: 모델 가중치를 S3에 업로드하는 플레이북 + **init container가 S3에서 모델을 다운로드**해 Pod에 마운트 — 이미지에 모델을 굽지 않아 이미지 크기·보안 부담 감소
- **CI 인증 자동화**: Jenkins에 GitHub deploy key 등록을 Ansible로 자동화, Vault로 시크릿 암호화
- **스케줄링 데드락 방지**: 롤링 업데이트 시 리소스 부족으로 새 Pod가 스케줄링되지 못하는 문제를 `maxSurge` 설정으로 해결
- **NAT 인스턴스 직접 구축**: NAT Gateway 대신 t3.nano NAT 인스턴스로 비용 절감 — `ip_forward`/`iptables MASQUERADE` 인터페이스명 이슈, 설정 덮어쓰기 오류를 직접 디버깅
- **kubelet ECR credential provider**: 프라이빗 노드가 ECR 이미지를 당겨오도록 credential provider 구성 (다운로드 링크 유실 이슈 해결 포함)

---

## 아키텍처 개요

```
  [ Web Client (React + Vite) ]
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
  │  │  프라이빗 트래픽    │  │  ECR Push + ArgoCD   │   │
  │  │  라우팅             │  │  이미지 태그 업데이트  │   │
  │  └────────┬────────────┘  └──────────┬──────────┘   │
  │           │ SSH ProxyJump            │ git push     │
  │                                                      │
  │  ┌─────────────────────────────────────────────┐    │
  │  │  ALB (Application Load Balancer)            │    │
  │  │  microlens.cloud                            │    │
  │  │  HTTP :80  → HTTPS 리다이렉트               │    │
  │  │  HTTPS :443 → Nginx Ingress NodePort 30080  │    │
  │  │  ACM 인증서 (microlens.cloud, *.microlens.cloud) │ │
  │  └───────────────────┬─────────────────────────┘    │
  │                      │              ECR (4개 리포지토리)│
  │  프라이빗 서브넷      │                               │
  │  ┌───────────────────▼──────────────────────────┐   │
  │  │  Kubernetes Cluster                          │   │
  │  │                                              │   │
  │  │  Control Plane (t3.medium)                   │   │
  │  │  └── ArgoCD (microlens-infra 저장소 감시)    │   │
  │  │                                              │   │
  │  │  CPU Worker (t3.large) ← 시스템 Pod 전용     │   │
  │  │  ┌──────────────────────────────────────┐   │   │
  │  │  │  ingress-nginx (NodePort 30080)      │   │   │
  │  │  │  metrics-server                      │   │   │
  │  │  │  microlens-client (React)            │   │   │
  │  │  │  stain-classification (CPU)          │   │   │
  │  │  └──────────────────────────────────────┘   │   │
  │  │                                              │   │
  │  │  Inference Worker × 2 (t3.xlarge)            │   │
  │  │  podAntiAffinity: required (노드 분산)        │   │
  │  │  ┌──────────────────────────────────────┐   │   │
  │  │  │  worker-1: stain-detection-1, teeth-1│   │   │
  │  │  │  worker-2: stain-detection-2, teeth-2│   │   │
  │  │  │  노드 1대 장애 시 나머지가 전체 흡수  │   │   │
  │  │  └──────────────────────────────────────┘   │   │
  │  │                                              │   │
  │  │  Nginx Ingress                               │   │
  │  │  /               → microlens-client          │   │
  │  │  /stain/detect   → stain-detection           │   │
  │  │  /stain/classify → stain-classification      │   │
  │  │  /teeth/check    → teeth                     │   │
  │  └──────────────────────────────────────────────┘   │
  │                                                      │
  │  S3: microlens-model-weights (모델 가중치)            │
  │  Route 53: microlens.cloud Hosted Zone              │
  └──────────────────────────────────────────────────────┘
```

---

## 디렉토리 구조

```
microlens-infra/
├── terraform/
│   ├── main.tf               # 모듈 orchestration (vpc, ec2, s3, ecr, route53, acm, alb)
│   ├── auth.tf               # IAM 그룹/사용자, SSH 키 페어
│   ├── backend.tf            # S3 원격 백엔드 + DynamoDB 락
│   ├── provider.tf           # AWS / TLS / Local 프로바이더
│   ├── outputs.tf            # 주요 리소스 출력값
│   └── modules/
│       ├── vpc/          # VPC, 퍼블릭·프라이빗 서브넷(각 2개), NAT 인스턴스, EIP
│       ├── ec2/          # Control Plane, Inference Worker, CPU Worker, Jenkins, IAM, SG
│       ├── s3/           # 모델 가중치 저장 버킷 (버전 관리 활성화)
│       ├── ecr/          # 컨테이너 이미지 레지스트리 (4개 리포지토리)
│       ├── route53/      # microlens.cloud Hosted Zone
│       ├── acm/          # SSL 인증서 발급 + Route 53 DNS 자동 검증
│       └── alb/          # ALB + HTTPS 리스너 + Target Group + A 레코드
│
├── ansible/
│   ├── ansible.cfg                    # 기본 설정 (키 경로, ProxyJump, vault)
│   ├── site.yml                       # 전체 실행 진입점
│   ├── inventory/
│   │   └── hosts.ini                  # 호스트 목록 (terraform output으로 IP 채우기)
│   ├── group_vars/
│   │   ├── all.yml                    # 공통 변수 (gpu_enabled, k8s_version)
│   │   ├── k8s.yml                    # Bastion ProxyJump SSH 설정
│   │   └── jenkins.yml                # Jenkins 변수 (Ansible Vault 암호화)
│   └── playbooks/
│       ├── 00-nat.yml                 # NAT ip_forward + iptables MASQUERADE
│       ├── 01-common.yml              # containerd + kubelet/kubeadm/kubectl + ECR credential provider
│       ├── 02-gpu.yml                 # NVIDIA Driver + Container Toolkit (gpu_enabled: true 시에만)
│       ├── 03-master.yml              # kubeadm init + Calico CNI + kubeconfig
│       ├── 04-worker.yml              # kubeadm join (cpu_workers)
│       ├── 05-addons.yml              # Metrics Server + Nginx Ingress(NodePort 30080 고정) + 노드 라벨
│       ├── 06-deploy-k8s.yml          # (Deprecated — ArgoCD가 대체)
│       ├── 07-jenkins.yml             # Jenkins + Docker + AWS CLI + kubectl + kustomize 설치
│       ├── 08-argocd.yml              # ArgoCD 설치 + microlens Application CRD 배포
│       ├── 09-upload-models.yml       # 모델 가중치 S3 업로드
│       └── 10-gpu-timeslicing.yml     # GPU Time-Slicing 설정 (gpu_enabled: true 환경 전용)
│
├── k8s/
│   ├── base/                          # 공통 리소스
│   │   ├── 00-namespace.yaml          # microlens 네임스페이스
│   │   ├── 00-serviceaccount.yaml     # S3/ECR 접근용 ServiceAccount
│   │   ├── 02-stain-classification.yaml  # CPU Deployment + Service
│   │   ├── 04-ingress.yaml            # Nginx Ingress L7 경로 라우팅 (AI API)
│   │   ├── 05-hpa.yaml                # HPA — stain-classification
│   │   ├── 06-client.yaml             # microlens-client Deployment + Service + Ingress
│   │   └── kustomization.yaml
│   │
│   └── overlays/
│       ├── phase1/                    # Phase 1 오버레이 (CPU만)
│       │   └── kustomization.yaml
│       └── phase2/                    # Phase 2 오버레이 (전체 서비스 + HA)
│           ├── 01-stain-detection.yaml   # CPU Deployment × 2 + podAntiAffinity + Service
│           ├── 03-teeth.yaml             # CPU Deployment × 2 + podAntiAffinity + Service
│           ├── 05-hpa-gpu.yaml           # HPA — stain-detection, teeth
│           └── kustomization.yaml        # 이미지 태그(commit SHA) 관리
│
└── argocd/
    └── application.yaml               # ArgoCD Application CRD 템플릿 (Jinja2)
```

---

## AMI 선택: Ubuntu 22.04 (Amazon Linux 2 대신)

모든 인스턴스의 AMI로 **Ubuntu 22.04 LTS (Canonical)** 를 사용합니다.

| 항목 | Amazon Linux 2 | Ubuntu 22.04 |
|------|---------------|--------------|
| NVIDIA 드라이버 설치 | CUDA rhel7 repo 수동 구성 + DKMS 빌드 | `ubuntu-drivers autoinstall` 한 줄 |
| CUDA 저장소 유지보수 | rhel7 기반, 업데이트 느림 | Ubuntu 전용 공식 repo, 활발히 유지 |
| K8s 공식 문서 기준 | rpm/yum 예시 드묾 | 거의 모든 공식 문서가 Ubuntu 기준 |
| 패키지 버전 고정 | `yum-plugin-versionlock` 별도 설치 | `apt-mark hold` 기본 내장 |
| 트러블슈팅 자료 | 커뮤니티 자료 제한적 | GPU + K8s 조합 자료 압도적으로 풍부 |

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| 클라우드 | AWS (EC2, ECR, S3, VPC, ALB, ACM, Route 53) |
| IaC | Terraform |
| 서버 구성 | Ansible |
| 컨테이너 오케스트레이션 | Kubernetes (kubeadm) |
| CNI | Calico (NetworkPolicy 지원, IPIP 모드) |
| K8s 패키지 관리 | Kustomize |
| GitOps | ArgoCD |
| CI/CD | Jenkins |
| AI 모델 | YOLOv12 (ONNX, opset 17+) |
| 추론 런타임 | ONNX Runtime (CPUExecutionProvider) |

---

## 인스턴스 구성

| 역할 | 타입 | 서브넷 | IAM 권한 |
|------|------|--------|----------|
| Bastion / NAT | t3.nano | 퍼블릭 | - |
| Jenkins | t3.medium | 퍼블릭 | ECR PowerUser, S3 ReadOnly |
| Control Plane | t3.medium | 프라이빗 | ECR ReadOnly, S3 ReadOnly |
| CPU Worker × 1 | t3.large | 프라이빗 | ECR ReadOnly, S3 ReadOnly |
| Inference Worker × 2 | t3.xlarge | 프라이빗 | ECR ReadOnly, S3 ReadOnly |

---

## 스케줄링 전략

```
Inference Worker (t3.xlarge) × 2
  Label:        node-type=cpu
  HA 전략:      podAntiAffinity required (동일 노드에 같은 앱 2개 배치 금지)
  배치 Pod:     stain-detection × 2, teeth × 2
  장애 시:      노드 1대 다운 → 나머지 노드가 두 서비스 모두 흡수

CPU Worker (t3.large) × 1
  Label:        node-type=cpu
  배치 Pod:     stain-classification
                microlens-client
                ingress-nginx, metrics-server
```

| 서비스 | 노드 타입 | replicas | nodeSelector | podAntiAffinity |
|--------|-----------|----------|--------------|-----------------|
| stain-detection | Inference Worker | 2 | node-type=cpu | required |
| stain-classification | CPU Worker | 1 | node-type=cpu | 없음 |
| teeth | Inference Worker | 2 | node-type=cpu | required |
| microlens-client | CPU Worker | 1 | node-type=cpu | 없음 |
| ingress-nginx | CPU Worker | - | 없음 | 없음 |
| metrics-server | CPU Worker | - | 없음 | 없음 |

### GPU 전환 시 (gpu_enabled: true)

GPU 추론이 필요한 경우 아래 값만 변경하면 됩니다.

```
# terraform/main.tf
worker_instance_type = "g4dn.xlarge"

# ansible/inventory/group_vars/all.yml
gpu_enabled: true

# ansible/inventory/hosts.ini
[gpu_workers] 그룹으로 worker-1, worker-2 이동
```

---

## 도메인 및 HTTPS 구성

### 트래픽 흐름

```
브라우저 → microlens.cloud (Route 53 A Alias)
  → ALB :443 (ACM 인증서, TLS 종료)
    → HTTP 리다이렉트: :80 → :443 (301)
  → K8s 워커 노드 NodePort 30080
  → Nginx Ingress Controller
  → /               → microlens-client-svc
  → /stain/detect   → stain-detection-svc  → /predict
  → /stain/classify → stain-classification-svc → /predict
  → /teeth/check    → teeth-svc           → /predict
```

### Ingress 분리 구조

AI API와 웹 클라이언트는 Ingress 오브젝트를 분리합니다.

| Ingress | 파일 | 어노테이션 | 대상 |
|---------|------|-----------|------|
| `microlens-ingress` | `04-ingress.yaml` | `rewrite-target: /predict` | AI API 3종 |
| `microlens-client-ingress` | `06-client.yaml` | 없음 | React 클라이언트 |

> rewrite-target 어노테이션은 Ingress 오브젝트 전체에 적용되기 때문에, 클라이언트(정적 파일 서빙)와 AI API(경로 rewrite 필요)를 같은 Ingress에 넣으면 클라이언트 라우팅이 깨집니다.

### Nginx Ingress NodePort 고정

ALB Target Group은 고정 포트(30080)를 바라봅니다. `05-addons.yml`에서 Nginx Ingress 설치 후 NodePort를 30080으로 패치합니다.

```
ALB → 워커 노드:30080 → Nginx Ingress Pod
```

---

## 배포 단계 (2-Phase 전략)

### Phase 1 — CPU 서비스만 배포

네트워크, Ingress 라우팅, 파이프라인 연결을 검증합니다.

```bash
# group_vars/all.yml: gpu_enabled: false
cd ansible
ansible-playbook site.yml

# ArgoCD가 k8s/overlays/phase1 를 감시하여 자동 배포
# → stain-classification(CPU) + microlens-client 배포됨
```

### Phase 2 — 전체 서비스 배포 (HA)

```bash
# 1. terraform/main.tf 확인
#    worker_instance_type = "t3.xlarge"
#    worker_count         = 2
terraform apply

# 2. hosts.ini IP 업데이트 후 Ansible 실행
ansible-playbook ansible/site.yml

# 3. ArgoCD Application을 phase2 오버레이로 업데이트
#    → stain-detection × 2, teeth × 2 (podAntiAffinity HA) 포함 전체 배포
ansible-playbook ansible/playbooks/08-argocd.yml -e argocd_overlay=phase2
```

### Jenkins CI 파이프라인 흐름

```
GitHub Push (microlens-ai-api 또는 microlens-client)
  → Jenkins Webhook 수신
  → Docker Build (VITE_API_BASE_URL="" — 상대 URL 사용)
  → ECR Push
  → kustomize edit set image (commit SHA 태그)
  → git push → ArgoCD 자동 감지 + 배포
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
cd terraform

# 1. 초기화 (backend.tf의 terraform 블록 주석 처리 상태에서 시작)
terraform init

# 2. 리소스 생성
terraform apply

# 3. S3 백엔드 활성화 (backend.tf 주석 해제 후)
terraform init -migrate-state

# 4. 출력값 확인 → ansible/inventory/hosts.ini IP 채우기
terraform output
```

### 도메인 연결 (가비아 → Route 53)

```bash
# terraform apply 완료 후 NS 레코드 4개 확인
terraform output route53_name_servers

# 가비아 콘솔 → 도메인 관리 → 네임서버 설정에 위 4개 입력
# DNS 전파 확인 (보통 수 분 이내)
dig NS microlens.cloud
```

> **주의**: `terraform apply` 중 `aws_acm_certificate_validation`이 대기 상태로 멈출 수 있습니다.
> 가비아에 네임서버를 입력하고 DNS가 전파되면 ACM 검증이 자동 완료되며 apply가 진행됩니다.

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
ansible-playbook site.yml --tags addons   # Ingress(NodePort 30080) + Metrics Server + 노드 라벨
ansible-playbook playbooks/07-jenkins.yml # Jenkins 설치
ansible-playbook playbooks/08-argocd.yml  # ArgoCD 설치 + Application 배포

# 워커 노드 신규 추가 시
ansible-playbook site.yml --tags common,worker --limit bastion,cpu_workers
ansible-playbook site.yml --tags addons
```

### 리소스 정리

```bash
make teardown   # microlens 네임스페이스 및 하위 모든 리소스 삭제
```

---

## 클러스터 상태 확인

kubectl은 Control Plane 한 곳에서 모든 노드/Pod 상태를 조회할 수 있습니다.

### 노드 상태

```bash
# 노드 목록 + 역할/상태
kubectl get nodes -o wide

# 노드별 라벨 확인 (node-type=cpu)
kubectl get nodes --show-labels

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

# 시스템 Pod 상태
kubectl get pods -n ingress-nginx -o wide
kubectl get pods -n kube-system -o wide
kubectl get pods -n argocd -o wide
```

### 자원 점유 상세

```bash
# 노드별 Pod 목록과 리소스 requests/limits
kubectl describe nodes | grep -A 20 "Allocated resources"

# 특정 Pod 상세 (스케줄링 이유, 이벤트 포함)
kubectl describe pod -n microlens <pod-name>

# HPA 상태 (현재 replica 수, CPU 사용률)
kubectl get hpa -n microlens
```

### ArgoCD 상태

```bash
# Application 동기화 상태 확인
kubectl get application -n argocd

# ArgoCD UI 접근 (포트포워딩)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 초기 admin 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 로그 확인

```bash
# 특정 서비스 로그
kubectl logs -n microlens -l app=stain-detection --tail=50
kubectl logs -n microlens -l app=stain-classification --tail=50
kubectl logs -n microlens -l app=teeth --tail=50
kubectl logs -n microlens -l app=microlens-client --tail=50

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

## YOLOv12 배포 주의사항

### readinessProbe 설정

YOLOv12 모델 로딩 시간이 YOLOv5 대비 길어지므로 `initialDelaySeconds`를 충분히 설정해야 합니다.

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 90
  periodSeconds: 10
  failureThreshold: 3
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 120
  periodSeconds: 15
  failureThreshold: 3
```

---

## 관련 저장소

- 🔬 [microlens-ai-api](https://github.com/MICRO-LENS/microlens-ai-api) — FastAPI AI 추론 서버 (YOLOv12 · ONNX Runtime)
- 💻 [microlens-client](https://github.com/MICRO-LENS/microlens-client) — React + Vite 웹 클라이언트
- 👕 [Stainless](https://github.com/catapillar0505/Stainless) — 전신 프로젝트 (2023 배리어프리 앱 개발 콘테스트 우수상)
