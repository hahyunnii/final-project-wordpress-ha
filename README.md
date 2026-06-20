# Final Project — WordPress HA + S3 on AWS

> **Cloud Computing & AWS — Semester Final Project**  
> Built on top of Assignment 6 (EC2 + RDS + ALB + ASG), extending to full stateless HA with S3 media offload and CloudWatch monitoring.

---

## Architecture

```
Internet
   │ HTTP/80
   ▼
[ALB]  ← alb-sg (0.0.0.0/0 → 80)
   │
   ├── [EC2: AZ-a]  ─┐
   └── [EC2: AZ-b]  ─┤  ASG (min=1, desired=2, max=3)
                      │  IAM Role → S3 access
                      │
                      ▼ MySQL/3306
               [RDS MySQL 8.0 Multi-AZ]
               publicly_accessible = false

[S3 Bucket]  ← WordPress 미디어 파일 저장소
               EC2 IAM Role로 인증 (Access Key 없음)

[CloudWatch Dashboard]
  - EC2 CPU / ALB RequestCount / ASG Instance Count
  - RDS CPU / DB Connections / Free Storage
  - S3 Object Count / Bucket Size
```

## What's New vs. Assignment 6

| 항목 | Assignment 6 | Final Project |
|---|---|---|
| 미디어 저장소 | EC2 로컬 디스크 | **S3 버킷 (Offload)** |
| EC2 → S3 인증 | 없음 | **IAM Role + Instance Profile** |
| CloudWatch | CPU 알람만 | **Dashboard + RDS 알람 추가** |
| 총 리소스 | 14개 | **20개** |

## Concepts from Class

| Week | Concept | This Project |
|---|---|---|
| 1~2 | Cloud 개념, S3, EC2 | S3 미디어 버킷, EC2 웹 서버 |
| 3~4 | S3 접근 제어 | S3 Bucket Policy, IAM Role |
| 5~6 | EC2 + ALB, AWS CLI | ALB + EC2, CLI 검증 명령어 |
| 7 | Terraform (IaC) | 전체 인프라 코드화 |
| 8 | Benchmarking | ab 부하 테스트 |
| 9~10 | CloudWatch + ASG | Dashboard + CPU 기반 자동 확장 |
| 11~12 | RDS | MySQL Multi-AZ |

## Quick Start

```bash
# 1. 환경변수 설정
export TF_VAR_db_master_password='Your-Password-Here'

# 2. tfvars 생성
cp terraform.tfvars.example terraform.tfvars

# 3. 배포
terraform init
terraform plan -out plan.out
terraform apply plan.out

# 4. 출력값 확인
terraform output

# 5. 정리
terraform destroy
```

## Deliverables

- `main.tf` — 전체 인프라 (S3, IAM, ALB, ASG, RDS, CloudWatch)
- `variables.tf` — 설정값
- `outputs.tf` — 배포 결과 출력
- `user-data.sh` — EC2 부트스트랩 + WP Offload Media 설정
- `commands.md` — 실행 명령어 로그
- `report.md` — 아키텍처 분석 및 수업 개념 연결
