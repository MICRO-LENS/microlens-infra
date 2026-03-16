# microlens-infra

MicroLens 프로젝트의 인프라스트럭처 전용 저장소입니다.
Terraform으로 AWS 리소스를 프로비저닝하고, Ansible로 서버를 구성하며, Kubernetes 매니페스트로 컨테이너를 배포합니다.

---

## 아키텍처 개요

```
                    ┌─────────────────────────────────────────┐
                    │               AWS Cloud                  │
                    │                                         │
  Android Client ──▶│  ALB (Application Load Balancer)        │
                    │    │                                     │
                    │    ▼                                     │
                    │  EKS Cluster                            │
                    │  ├── stain-api Pod  (얼룩 탐지)          │
                    │  └── teeth-api Pod  (치아 확인)          │
                    │         │                               │
                    │         ▼                               │
                    │  ECR (Container Registry)               │
                    │  S3  (모델 가중치 파일 저장)              │
                    └─────────────────────────────────────────┘
```

---

## 디렉토리 구조

```
microlens-infra/
├── terraform/
│   ├── modules/
│   │   ├── vpc/          # VPC, 서브넷, 보안 그룹
│   │   ├── eks/          # EKS 클러스터 및 노드 그룹
│   │   ├── ecr/          # 컨테이너 이미지 레지스트리
│   │   └── s3/           # 모델 가중치 저장 버킷
│   ├── environments/
│   │   ├── dev/
│   │   └── prod/
│   └── example.tfvars    # 변수 예시 (실제 값은 *.tfvars로 로컬 관리)
├── ansible/
│   ├── playbooks/
│   │   ├── setup.yml     # 기본 서버 환경 설정
│   │   └── deploy.yml    # 애플리케이션 배포
│   └── inventory/
│       └── example/      # 인벤토리 예시
└── k8s/
    ├── stain-api/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── hpa.yaml      # Horizontal Pod Autoscaler
    └── teeth-api/
        ├── deployment.yaml
        ├── service.yaml
        └── hpa.yaml
```

---

## 기술 스택

| 분류 | 기술 |
|------|------|
| 클라우드 | AWS (EKS, ECR, ALB, S3, VPC) |
| IaC | Terraform |
| 서버 구성 | Ansible |
| 컨테이너 오케스트레이션 | Kubernetes |

---

## 배포 전략

- **무중단 배포**: Kubernetes RollingUpdate 전략 사용
- **오토스케일링**: HPA로 CPU/메모리 기준 Pod 자동 확장
- **모델 가중치**: S3에 저장 후 Pod 기동 시 마운트 (Git에 커밋하지 않음)

---

## 시작하기

### 사전 요구사항

- Terraform >= 1.5
- AWS CLI (자격 증명 설정 완료)
- kubectl
- Ansible >= 2.14

### Terraform 실행

```bash
cd terraform/environments/dev
cp ../../example.tfvars terraform.tfvars  # 값 채운 후 사용
terraform init
terraform plan
terraform apply
```

> **주의**: `*.tfvars`, `*.tfstate`, 자격 증명 파일은 절대 커밋하지 않습니다.

---

## 관련 저장소

- [microlens-ai-api](../microlens-ai-api) — FastAPI 백엔드 서버
- [microlens-android](../microlens-android) — Android 클라이언트 앱
