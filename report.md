# Lab Report — RDS-Backed HA WordPress on EC2 + RDS

**Course:** Cloud Computing & AWS  
**Assignment:** Week 12 — EC2 + RDS with Terraform (HA Extension)  
**Due Date:** June 20, 2026  
**Repository:** https://github.com/mobile-os-dku-cis-mse/06-ec2-rds-with-terraform-hahyunnii  


---

## 1. Objective

Week 12 단일 EC2 WordPress 베이스라인을 **High-Availability(HA) 아키텍처**로 확장.

- **ALB(Application Load Balancer)** 로 트래픽을 다수의 EC2에 분산
- **ASG(Auto Scaling Group)** 으로 EC2 자동 복구 및 수평 확장
- **RDS MySQL Multi-AZ** 로 데이터베이스 단일장애점 제거
- 보안 경계 유지: `publicly_accessible = false`, SG-only DB 접근

---

## 2. Architecture

### 2.1 Diagram

```
                         Internet
                            │ HTTP/80
                            ▼
                ┌───────────────────────┐
                │  Application Load     │  sg-alb (sg-0f5b65c7c67426864)
                │  Balancer (ALB)       │  0.0.0.0/0 → 80
                │  wp-ha-rds-alb        │
                └──────────┬────────────┘
                           │ HTTP/80 (alb-sg → wordpress-sg)
               ┌───────────┼───────────┐
               ▼                       ▼
      ┌──────────────────┐    ┌──────────────────┐
      │  EC2 WordPress   │    │  EC2 WordPress   │
      │  i-0d01ae088fcb  │    │  i-07beca60a583  │  Auto Scaling Group
      │  18.209.221.1    │    │  18.212.176.211  │  wp-ha-rds-asg
      │  us-east-1a      │    │  us-east-1b      │  min=1 desired=2 max=3
      └────────┬─────────┘    └────────┬─────────┘  sg-wordpress (sg-0d655c34f11996faf)
               └──────────┬────────────┘
                          │ MySQL/3306 (wordpress-sg → rds-sg)
                          ▼
              ┌────────────────────────────┐
              │  RDS MySQL 8.0 Multi-AZ    │  sg-rds (sg-01d0cd90b0994177e)
              │  wp-ha-rds-mysql           │  wordpress-sg → 3306 only
              │  Primary:  us-east-1a      │  publicly_accessible = false
              │  Standby:  us-east-1b      │
              │  db-A6TLMTZ6PAAVDOCEKLWUFY4EVI │
              └────────────────────────────┘
```

### 2.2 실제 배포 리소스

| # | Terraform Resource | AWS Name / ID | 역할 |
|---|---|---|---|
| 1 | `aws_security_group.alb` | `sg-0f5b65c7c67426864` | ALB — 인터넷 HTTP/80 허용 |
| 2 | `aws_security_group.wordpress` | `sg-0d655c34f11996faf` | EC2 — ALB에서 HTTP/80만 허용 |
| 3 | `aws_security_group.rds` | `sg-01d0cd90b0994177e` | RDS — EC2 SG에서 TCP/3306만 허용 |
| 4 | `aws_db_subnet_group.wordpress` | `wp-ha-rds-db-subnets` | RDS 서브넷 그룹 |
| 5 | `aws_db_instance.wordpress` | `wp-ha-rds-mysql` / `db-A6TLMTZ6PAAVDOCEKLWUFY4EVI` | MySQL 8.0 Multi-AZ, db.t3.micro, 20 GiB |
| 6 | `aws_lb.wordpress` | `wp-ha-rds-alb` | ALB — 2개 AZ에 걸쳐 배포 |
| 7 | `aws_lb_target_group.wordpress` | `wp-ha-rds-tg` | `/health.html` 헬스체크 |
| 8 | `aws_lb_listener.http` | — | HTTP/80 → Target Group 포워딩 |
| 9 | `aws_launch_template.wordpress` | `lt-090a22a836817a026` | EC2 설정 + user_data (RDS/ALB 변수 포함) |
| 10 | `aws_autoscaling_group.wordpress` | `wp-ha-rds-asg` | min=1 desired=2 max=3, 2개 AZ |
| 11 | `aws_autoscaling_policy.scale_out` | `wp-ha-rds-scale-out` | CPU > 70% → +1 인스턴스 |
| 12 | `aws_autoscaling_policy.scale_in` | `wp-ha-rds-scale-in` | CPU < 30% → -1 인스턴스 |
| 13 | `aws_cloudwatch_metric_alarm.cpu_high` | `wp-ha-rds-cpu-high` | scale-out 트리거 |
| 14 | `aws_cloudwatch_metric_alarm.cpu_low` | `wp-ha-rds-cpu-low` | scale-in 트리거 |

---

## 3. Key Design Decisions

### 3.1 ALB — 단일 EC2 Public IP 대체

기존 Week 12는 EC2 퍼블릭 IP를 브라우저에 직접 노출했음. ALB 도입으로:
- 인스턴스가 교체되어도 DNS(`wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com`)가 변하지 않음
- ALB가 `/health.html` 헬스체크를 수행하여 통과한 인스턴스에만 트래픽 전달
- EC2 SG(`sg-0d655c34f11996faf`)는 ALB SG에서의 포트 80만 허용 — EC2 직접 접근 불가

### 3.2 WP_HOME / WP_SITEURL = ALB DNS

ALB 뒤에서 WordPress가 잘못된 URL(EC2 private DNS)을 생성하는 문제 방지.
`user-data.sh`에서 `wp-config.php`에 아래를 추가:

```php
define( 'WP_HOME',    'http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com' );
define( 'WP_SITEURL', 'http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com' );
```

어느 EC2 인스턴스가 요청을 처리하더라도 동일한 ALB URL로 링크/리다이렉트가 생성됨.

### 3.3 RDS Multi-AZ

`multi_az = true` → AWS가 `us-east-1b`에 동기식 Standby 복제본 자동 생성.
Primary(us-east-1a) 장애 시 약 60~120초 내 자동 Failover. RDS 엔드포인트 DNS는 Failover 후에도 동일하게 유지되어 `wp-config.php` 수정 불필요.

### 3.4 Security Group Chain

```
인터넷 → alb-sg (0.0.0.0/0:80)
       → wordpress-sg (alb-sg:80)
       → rds-sg (wordpress-sg:3306)
```

각 레이어는 바로 상위 SG만 신뢰. `wordpress-sg`의 80포트에 CIDR `0.0.0.0/0` 없음. `rds-sg`에 CIDR 규칙 전혀 없음.

### 3.5 Launch Template + ASG

기존 `aws_instance` → `aws_launch_template` + `aws_autoscaling_group` 교체:
- **수평 확장**: 2개 AZ에 동일한 인스턴스 자동 배포
- **자가 복구**: 비정상 인스턴스 자동 교체
- **Rolling 업데이트**: `aws autoscaling start-instance-refresh`로 무중단 교체

### 3.6 Terraform templatefile 이슈 해결

`user-data.sh`에서 bash 배열 변수 `${LAMP_PACKAGES[@]}`를 Terraform이 template 변수로 오해하는 오류 발생.
bash 변수는 `$${LAMP_PACKAGES[@]}`로 이스케이프하여 해결.

---

## 4. 실습 실제 결과

### 4.1 배포 확인

```
# health_check_url 응답
ok
name_prefix=wp-ha-rds
instance_id=i-07beca60a583fe60d
availability_zone=us-east-1b
database_host=wp-ha-rds-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com
database_name=wordpressdb

# db_check_url 응답
db-ok
```

### 4.2 WordPress 사이트

- **URL**: `http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/`
- **Site Title**: WordPress HA Lab
- **상태**: 설치 완료, 사이트 정상 동작 확인 (Blog 화면, "Hello world!" 포스트 출력)
- WordPress 테이블이 RDS MySQL(`wordpressdb`) 에 저장됨 — EC2 로컬 디스크 아님

### 4.3 ASG 인스턴스 분산

| Instance ID | Public IP | AZ |
|---|---|---|
| `i-0d01ae088fcb0f542` | `18.209.221.1` | `us-east-1a` |
| `i-07beca60a583fe60d` | `18.212.176.211` | `us-east-1b` |

---

## 5. 베이스라인 대비 변경사항

| 항목 | Week 12 베이스라인 | 이번 HA 확장 |
|---|---|---|
| 웹 접근 진입점 | EC2 퍼블릭 IP | ALB DNS (안정적, Multi-AZ) |
| EC2 배포 | 단일 `aws_instance` | ASG + Launch Template (desired=2) |
| AZ 커버리지 | 1개 AZ | 2개 AZ (us-east-1a, us-east-1b) |
| EC2 접근 | `0.0.0.0/0` 포트 80 | ALB SG에서만 |
| 자동 복구 | 없음 | ASG가 비정상 인스턴스 자동 교체 |
| 자동 확장 | 없음 | CloudWatch CPU 알람 + ASG 정책 |
| RDS 모드 | Single-AZ | Multi-AZ (동기식 Standby) |
| WordPress URL 설정 | EC2 DNS / localhost | ALB DNS (`WP_HOME`, `WP_SITEURL`) |
| 총 리소스 수 | 5개 | 14개 |

---

## 6. HA 장애 시나리오

### 6.1 EC2 인스턴스 1개 장애
1. ALB 헬스체크(`GET /health.html`) 3회 연속 실패 (약 90초)
2. ALB가 해당 인스턴스로 트래픽 전송 중단
3. ASG가 비정상 인스턴스 감지 후 종료 및 신규 인스턴스 시작
4. 신규 인스턴스가 부트스트랩 완료 후 ALB에 등록
5. **사용자 체감 다운타임: 0초** (나머지 AZ 인스턴스가 지속 서비스)

### 6.2 AZ 전체 장애
1. ALB가 장애 AZ의 모든 타겟 제거
2. 정상 AZ 인스턴스로 트래픽 집중
3. ASG가 정상 AZ에 추가 인스턴스 시작
4. RDS Multi-AZ Failover: Standby(us-east-1b) → Primary 승격
5. **예상 다운타임: 60~120초** (RDS Failover 시간)

### 6.3 RDS Primary 장애
1. AWS가 Primary 장애 감지 후 Standby 자동 승격
2. RDS 엔드포인트 DNS TTL이 짧아 60초 내 재연결
3. `wp-config.php` 수정 불필요 (엔드포인트 DNS 동일 유지)

---

## 7. 남은 한계점

| 한계 | 영향 | 향후 해결책 |
|---|---|---|
| WordPress 미디어 파일이 EC2 로컬 디스크 | EC2 교체 시 업로드 파일 손실, ASG 인스턴스 간 미공유 | Amazon EFS 공유 마운트 |
| HTTP만 지원 (HTTPS 없음) | 관리자 비밀번호 평문 전송 | ACM 인증서 + ALB HTTPS 리스너 |
| 단일 리전 배포 | 리전 장애 시 전체 서비스 중단 | Route 53 + 멀티 리전 Standby |
| CDN 없음 | 원거리 사용자 지연 | CloudFront |

---

## 8. Conclusion

이번 과제에서 Week 12 단일 EC2 + RDS 베이스라인을 ALB + ASG + RDS Multi-AZ 구조로 확장하여 프로덕션 수준의 HA 아키텍처를 Terraform으로 구현했다.

핵심 추가사항:
- **ALB**: 안정적인 DNS 제공, EC2 직접 노출 제거
- **ASG**: 2개 AZ에 걸친 자가 복구 및 수평 확장
- **RDS Multi-AZ**: 데이터베이스 자동 Failover
- **WP_HOME/WP_SITEURL**: ALB DNS 고정으로 URL 정합성 보장

실제 배포에서 `health_check_url → ok`, `db_check_url → db-ok` 확인 및 WordPress 사이트 정상 동작을 검증하였으며, `terraform destroy`로 14개 리소스 전체 삭제 완료.
