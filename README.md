# Final Project — WordPress HA + S3 on AWS

> **Cloud Computing & AWS — Semester Final Project**

Assignment 6(EC2 + RDS + ALB + ASG)을 베이스라인으로, **S3 미디어 Offload**, **CloudWatch 통합 모니터링**, **ab 벤치마크 테스트**를 추가하여 수업 Week 1~12의 모든 개념을 하나의 HA WordPress 서비스로 통합 구현하였다.

---

## Architecture

```
Internet
   │ HTTP/80
   ▼
[ALB: wp-final-alb]          ← sg-alb (0.0.0.0/0 → 80)
   │
   ├── [EC2: us-east-1a]  ─┐
   └── [EC2: us-east-1b]  ─┤  ASG (min=1, desired=2, max=3)
                            │  IAM Role: LabRole → S3 접근
                            ▼ MySQL/3306
                     [RDS MySQL 8.0 Multi-AZ]
                     publicly_accessible = false

[S3: wp-final-media-980808829165]
  ← WordPress 미디어 자동 Offload (WP Offload Media Lite)
  ← IAM Role 인증 (Access Key 불필요)

[CloudWatch Dashboard: wp-final-dashboard]
  ← EC2 / ALB / ASG / RDS / S3 실시간 모니터링 (7개 위젯)
```

---

## What's New vs. Assignment 6

| 항목 | Assignment 6 | Final Project |
|---|---|---|
| 미디어 저장소 | EC2 로컬 디스크 | **S3 버킷 (자동 Offload)** |
| EC2 Stateless | ❌ | ✅ |
| IAM Role | 없음 | **LabRole** |
| CloudWatch | CPU 알람 2개 | **Dashboard 7위젯 + RDS 알람 2개** |
| Benchmarking | 없음 | **ab 부하 테스트** |
| 총 리소스 | 14개 | **25개** |
| 수업 커버리지 | Week 5~12 | **Week 1~12 전체** |

---

## Concepts from Class

| Week | 수업 내용 | 적용 |
|---|---|---|
| 1~2 | Cloud 개념, S3, EC2, IAM | S3 버킷, EC2, LabRole |
| 3~4 | S3 접근 제어, Bucket Policy | S3 Public Read, CORS |
| 5~6 | EC2 + ALB, AWS CLI | ALB 분산, CLI 검증 |
| 7 | Terraform IaC | 25개 리소스 코드화 |
| 8 | Benchmarking (ab) | C=10/C=40 부하 테스트 |
| 9~10 | CloudWatch + ASG | Dashboard + CPU 자동 확장 |
| 11~12 | RDS | MySQL Multi-AZ |

---

## Quick Start

```bash
# 1. 환경변수 설정
export TF_VAR_db_master_password='Your-Password-Here'

# 2. tfvars 생성
cp terraform.tfvars.example terraform.tfvars

# 3. 배포 (약 15분 소요 — RDS Multi-AZ 생성)
terraform init
terraform plan -out plan.out
terraform apply plan.out

# 4. 출력값 확인
terraform output

# 5. 정리
terraform destroy
```

---

## Deliverables

| 파일 | 내용 |
|---|---|
| `main.tf` | 전체 인프라 (S3, IAM, ALB, ASG, RDS, CloudWatch) |
| `variables.tf` | 설정값 |
| `outputs.tf` | 배포 결과 출력 |
| `versions.tf` | Provider 버전 고정 |
| `user-data.sh` | EC2 bootstrap (WordPress + WP_HOME/WP_SITEURL 설정) |
| `terraform.tfvars.example` | 설정 예시 (비밀번호 제외) |
| `commands.md` | 실행 명령어 로그 (실제값 포함) |
| `report.md` | 아키텍처 분석 및 수업 개념 연결 |

---

## Real Deployment Values

| Resource | Value |
|---|---|
| ALB DNS | `wp-final-alb-1657988911.us-east-1.elb.amazonaws.com` |
| WordPress URL | `http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/` |
| RDS Endpoint | `wp-final-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com` |
| S3 Bucket | `wp-final-media-980808829165` |
| CloudWatch Dashboard | `wp-final-dashboard` |
| EC2 AZ-a | `i-07b33d926afe269c8` / `us-east-1a` |
| EC2 AZ-b | `i-0155d46e46d7633b4` / `us-east-1b` |

---

## Benchmark Results

| Metric | Baseline (C=10, N=100) | Load (C=40, N=500) |
|---|---|---|
| Requests/sec | 19.65 | 22.15 |
| 평균 응답시간 | 508 ms | 1,805 ms |
| p95 응답시간 | 650 ms | 2,282 ms |
| Failed requests | **0** | **0** |
