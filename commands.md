# Commands Log — Final Project: WordPress HA + S3

## 0. 사전 준비

**1) AWS Academy → "Start Lab" → 상단 점이 🟢으로 바뀌면 준비 완료**

**2) "AWS Details" 버튼 클릭 → 자격증명 복사 후 터미널에 붙여넣기**

```bash
export AWS_ACCESS_KEY_ID="<paste>"
export AWS_SECRET_ACCESS_KEY="<paste>"
export AWS_SESSION_TOKEN="<paste>"
```

**3) RDS 비밀번호를 환경변수로 설정 (terraform.tfvars에 넣지 않는다)**

```bash
export TF_VAR_db_master_password='WpLabPass123!'
```

**4) 저장소 클론 및 브랜치 이동**

```bash
git clone https://github.com/hahyunnii/final-project-wordpress-ha.git
cd final-project-wordpress-ha
git checkout final-project
```

## 1. Preflight

```bash
# AWS Academy temporary credentials 확인
test -n "$AWS_ACCESS_KEY_ID"          && echo "AWS_ACCESS_KEY_ID is set"
test -n "$AWS_SECRET_ACCESS_KEY"      && echo "AWS_SECRET_ACCESS_KEY is set"
test -n "$AWS_SESSION_TOKEN"          && echo "AWS_SESSION_TOKEN is set"
test -n "$TF_VAR_db_master_password"  && echo "TF_VAR_db_master_password is set"

# credentials가 정상인지 확인
aws sts get-caller-identity

# region 확인
aws configure get region

# Terraform 설치 확인
terraform version
```

Key output:
```
AWS_ACCESS_KEY_ID is set
AWS_SECRET_ACCESS_KEY is set
AWS_SESSION_TOKEN is set
TF_VAR_db_master_password is set

{
    "UserId": "AROA6IXGDBDW3VDSMGKJG:user4886845=_________",
    "Account": "980808829165",
    "Arn": "arn:aws:sts::980808829165:assumed-role/voclabs/user4886845=_________"
}

us-east-1

Terraform v1.7.5
on linux_amd64
```

Interpretation:
- AWS 자격증명 3개(ACCESS_KEY_ID, SECRET_ACCESS_KEY, SESSION_TOKEN) 모두 설정됨. SESSION_TOKEN은 Academy 환경에서 필수
- region은 us-east-1로 설정됨
- Terraform v1.7.5 — 요구사항(>= 1.5.0) 충족

## 2. Init and Format

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
```

Key output:
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Interpretation:
- AWS provider v5.100.0 설치 완료. ~> 5.0 제약 조건 충족
- terraform fmt가 파일들의 포맷을 정규화함

## 3. Validate and Plan

```bash
terraform validate
terraform plan -out plan.out
```

Key output:
```
Success! The configuration is valid.

Terraform will perform the following actions:

  # aws_s3_bucket.wordpress_media will be created
  # aws_cloudwatch_dashboard.wordpress will be created
  # aws_cloudwatch_metric_alarm.rds_cpu_high will be created
  # aws_cloudwatch_metric_alarm.rds_storage_low will be created
  # aws_db_instance.wordpress [multi_az=true] will be created
  # aws_autoscaling_group.wordpress will be created
  # aws_lb.wordpress will be created
  # (+ 18 more resources)

Plan: 25 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + s3_bucket_name           = (known after apply)
  + cloudwatch_dashboard_url = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=wp-final-dashboard"
  + ec2_iam_role_name        = "LabRole"
  + selected_subnet_ids      = [
      + "subnet-0b325a3a157bfff42",
      + "subnet-0907c242196e43f14",
    ]
  + vpc_id                   = "vpc-099a13dbc423e5700"

Saved the plan to: plan.out
```

Interpretation:
- 총 25개 리소스 생성 예정 (Assignment 6의 14개 + S3 5개 + CloudWatch Dashboard 1개 + RDS 알람 2개 + data sources 등)
- AWS Academy는 IAM Role 생성 권한이 없어 기존 LabRole을 data source로 참조
- RDS Multi-AZ, S3, CloudWatch Dashboard가 Assignment 6 대비 추가됨

## 4. Apply

> ⚠️ RDS Multi-AZ 생성으로 인해 약 10~15분 소요. 완료될 때까지 기다린다.

```bash
terraform apply plan.out
terraform output
```

Key output:
```
aws_s3_bucket.wordpress_media: Creation complete [id=wp-final-media-980808829165]
aws_security_group.alb: Creation complete after 3s [id=sg-0547e2f86c9fd0ff8]
aws_security_group.wordpress: Creation complete after 3s [id=sg-0df92ea4c5d4e45d1]
aws_security_group.rds: Creation complete after 3s [id=sg-04a8c592eafad89b8]
aws_lb.wordpress: Creation complete after 2m52s
aws_db_instance.wordpress: Creation complete after 15m30s [id=db-VJA4IMTR2S5Q4VWVAGI6KPGT5E]
aws_launch_template.wordpress: Creation complete [id=lt-079d260e6f4841c88]
aws_autoscaling_group.wordpress: Creation complete [id=wp-final-asg]
aws_cloudwatch_dashboard.wordpress: Creation complete [id=wp-final-dashboard]

Apply complete! Resources: 25 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name             = "wp-final-alb-1657988911.us-east-1.elb.amazonaws.com"
asg_name                 = "wp-final-asg"
cloudwatch_dashboard_url = "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=wp-final-dashboard"
db_check_url             = "http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/db-health.php"
ec2_iam_role_name        = "LabRole"
health_check_url         = "http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/health.html"
launch_template_id       = "lt-079d260e6f4841c88"
rds_endpoint             = "wp-final-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com"
rds_instance_id          = "wp-final-mysql"
rds_multi_az             = true
rds_port                 = 3306
s3_bucket_name           = "wp-final-media-980808829165"
s3_bucket_arn            = "arn:aws:s3:::wp-final-media-980808829165"
s3_bucket_url            = "https://wp-final-media-980808829165.s3.us-east-1.amazonaws.com"
security_group_ids       = {
  "alb"       = "sg-0547e2f86c9fd0ff8"
  "rds"       = "sg-04a8c592eafad89b8"
  "wordpress" = "sg-0df92ea4c5d4e45d1"
}
selected_subnet_ids      = [
  "subnet-0b325a3a157bfff42",
  "subnet-0907c242196e43f14",
]
vpc_id                   = "vpc-099a13dbc423e5700"
wordpress_url            = "http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/"
```

Interpretation:
- 25개 리소스 모두 생성 완료. RDS Multi-AZ 생성에 약 15분 30초 소요 — 정상 동작
- S3 버킷 `wp-final-media-980808829165` 생성 완료
- CloudWatch Dashboard `wp-final-dashboard` 생성 완료
- EC2 IAM Role: LabRole (Academy 환경 제약으로 기존 Role 재사용)

## 5. Verify WordPress EC2 and RDS Connection

> ⚠️ apply 완료 후 EC2 bootstrap에 약 3~5분 소요. `ok` 응답이 올 때까지 기다린다.

```bash
# EC2 bootstrap 완료 확인
curl "$(terraform output -raw health_check_url)"

# PHP → RDS 연결 확인
curl "$(terraform output -raw db_check_url)"

# RDS Multi-AZ 및 공개 여부 확인
aws rds describe-db-instances \
  --db-instance-identifier "$(terraform output -raw rds_instance_id)" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Public:PubliclyAccessible,MultiAZ:MultiAZ}'

# ASG 인스턴스 2개가 2개 AZ에 분산됐는지 확인
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=wp-final-asg" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,Placement.AvailabilityZone]' \
  --output table

# S3 버킷 생성 확인
aws s3 ls "$(terraform output -raw s3_bucket_name)"

# EC2 → S3 IAM Role 접근 테스트 (EC2 Instance Connect에서 실행)
echo "test" > /tmp/s3test.txt
aws s3 cp /tmp/s3test.txt s3://wp-final-media-980808829165/test.txt
aws s3 ls s3://wp-final-media-980808829165
```

Key output:
```
# curl health_check_url
ok
name_prefix=wp-final
instance_id=i-07b33d926afe269c8
availability_zone=us-east-1a
database_host=wp-final-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com
database_name=wordpressdb
s3_bucket=wp-final-media-980808829165

# curl db_check_url
db-ok

# RDS 상태
{
    "Status": "available",
    "Public": false,
    "MultiAZ": true
}

# ASG 인스턴스
---------------------------------------------------------
|                   DescribeInstances                   |
+---------------------+------------------+--------------+
|  i-0155d46e46d7633b4|  34.239.103.143  |  us-east-1b  |
|  i-07b33d926afe269c8|  44.211.183.147  |  us-east-1a  |
+---------------------+------------------+--------------+

# EC2 → S3 접근 테스트
upload: ../../../tmp/s3test.txt to s3://wp-final-media-980808829165/test.txt
2026-06-20 04:31:12    5 test.txt
```

Interpretation:
- `health_check_url` → `ok`: EC2 bootstrap 완료, S3 버킷 정보 포함
- `db_check_url` → `db-ok`: PHP → RDS 연결 성공
- RDS `Public=false`, `MultiAZ=true`: 보안 경계 및 HA 확인
- EC2 2개가 us-east-1a, us-east-1b에 각각 배치 → HA 웹 티어 확인
- EC2 → S3 직접 접근 성공: LabRole IAM 인증 정상 동작

## 6. Verify Security Group Boundary

```bash
# RDS SG — 3306을 EC2 SG source에만 열어야 한다
aws ec2 describe-security-groups \
  --group-ids "$(terraform output -json security_group_ids | jq -r '.rds')" \
  --query 'SecurityGroups[0].IpPermissions'
```

Key output:
```json
[
    {
        "FromPort": 3306,
        "IpProtocol": "tcp",
        "IpRanges": [],
        "UserIdGroupPairs": [
            {
                "Description": "MySQL from WordPress EC2",
                "GroupId": "sg-0df92ea4c5d4e45d1",
                "UserId": "980808829165"
            }
        ]
    }
]
```

Interpretation:
- `IpRanges` 비어있음 — 0.0.0.0/0 없음, 인터넷에서 RDS 직접 접근 불가
- `UserIdGroupPairs`에 WordPress EC2 SG(`sg-0df92ea4c5d4e45d1`)만 허용
- EC2 → S3는 IAM Role(LabRole)로 인증, Access Key 코드에 불필요

## 7. WordPress 설치 및 S3 Offload Media 설정

```text
# 브라우저에서 WordPress 설치
URL: http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/

Site Title: WordPress
Admin Username: admin
Admin Email: lovehh329@naver.com
→ Install WordPress 클릭 → RDS MySQL에 WordPress 테이블 생성됨

# WP Offload Media Lite 플러그인 설치
WordPress Admin → Plugins → Add New Plugin
→ "WP Offload Media Lite" 검색 → Install Now → Activate

# 플러그인 파일 쓰기 권한 설정 (EC2 Instance Connect에서)
sudo sed -i "s|/* That's all|define('FS_METHOD', 'direct');\n\n/* That's all|" \
  /var/www/html/wp-config.php
sudo chown -R apache:apache /var/www/html/wp-content
sudo chmod -R 775 /var/www/html/wp-content

# WP Offload Media 설정
WordPress Admin → Settings → WP Offload Media
→ Amazon S3 선택
→ "My server is on Amazon Web Services and I'd like to use IAM Roles" 선택
→ Save & Continue
→ Bucket 이름 입력: wp-final-media-980808829165
→ Save Bucket Settings → Keep Bucket Security As Is
```

Key output:
```
Storage provider is successfully connected and ready to offload new media.
Amazon S3: wp-final-media-980808829165 (US East - N. Virginia)
Offload Media: ON

# 미디어 업로드 후 S3 확인
$ aws s3 ls s3://wp-final-media-980808829165 --recursive

2026-06-19 21:55:55  65395  wp-content/uploads/2026/06/20045554/스크린샷.png
2026-06-19 21:55:55  12188  wp-content/uploads/2026/06/20045554/스크린샷-150x150.png
2026-06-19 21:55:55  30493  wp-content/uploads/2026/06/20045554/스크린샷-300x257.png

# WordPress Media Library에서 확인한 파일 정보
Storage Provider: Amazon S3
Bucket: wp-final-media-980808829165
Region: US East (N. Virginia)
File URL: http://wp-final-media-980808829165.s3.amazonaws.com/...
Access: Public
```

Interpretation:
- WordPress 미디어 업로드 시 S3에 자동 복사됨
- 원본 + 썸네일(150x150, 300x257) 모두 S3에 저장됨
- 미디어 URL이 S3 도메인으로 서빙됨 — EC2 로컬 디스크 의존성 제거
- ASG 인스턴스 교체 시에도 미디어 파일 보존

## 8. Benchmark Test

```bash
# ab 설치 확인
which ab || sudo dnf install -y httpd-tools

# 테스트 1: 베이스라인 (낮은 부하)
ab -n 100 -c 10 http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/

# 테스트 2: 부하 테스트 (높은 동시성)
ab -n 500 -c 40 http://wp-final-alb-1657988911.us-east-1.elb.amazonaws.com/
```

Key output:
```
# Scenario 1 (C=10, N=100)
Requests per second:    19.65 [#/sec]
Time per request:       508.824 [ms] (mean)
Failed requests:        0
Transfer rate:          1348.37 [Kbytes/sec]
  50%    497 ms
  95%    650 ms
  99%    711 ms

# Scenario 2 (C=40, N=500)
Requests per second:    22.15 [#/sec]
Time per request:       1805.679 [ms] (mean)
Failed requests:        0
Transfer rate:          1519.84 [Kbytes/sec]
  50%   1769 ms
  95%   2282 ms
  99%   2562 ms
```

Interpretation:
- Failed requests: 0 — 높은 부하에서도 단 한 건의 요청 실패 없음. ALB + ASG 안정성 확인
- C=40에서 응답시간이 508ms → 1,805ms로 증가. t3.micro 2개의 처리 한계에 근접
- 벤치마크 실행 중 CloudWatch Dashboard에서 ALB RequestCount 스파이크와 ResponseTime 증가가 실시간으로 반영됨
- CPU 알람 임계값(70%)에 도달하면 ASG scale-out 정책이 자동으로 인스턴스를 추가하여 대응 가능

## 9. Verify CloudWatch Dashboard

```bash
# CloudWatch Dashboard URL 출력
terraform output -raw cloudwatch_dashboard_url
```

Key output:
```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=wp-final-dashboard

Dashboard: wp-final-dashboard (7개 위젯)
- EC2 CPU Utilization (ASG)     — Scale-out(70%) / Scale-in(30%) threshold 라인
- ALB Request Count & RT        — 벤치마크 트래픽 스파이크 확인
- ASG Instance Count            — Desired / InService 인스턴스 수
- RDS CPU & DB Connections      — DB 부하 모니터링
- RDS Free Storage Space        — 스토리지 잔량 추적
- ALB Healthy Host Count        — 정상 인스턴스 수 확인
- S3 Object Count & Size        — 미디어 파일 증가 추세

CloudWatch Alarms:
- wp-final-rds-cpu-high:    RDS CPU > 80%  → 경보
- wp-final-rds-storage-low: RDS 여유 스토리지 < 2GiB → 경보
```

Interpretation:
- 실제 ALB 트래픽, RDS CPU/연결 수, ASG 인스턴스 수가 실시간으로 수집됨
- 벤치마크 테스트 중 RequestCount 스파이크와 ResponseTime 증가가 Dashboard에서 실시간 확인됨
- Week 8에서 배운 "Benchmark Output → CloudWatch Metric → Operational Decision" 흐름을 실제로 검증

## 10. Troubleshooting

### 문제 1: IAM Role 생성 권한 없음
**증상:** `AccessDenied: iam:CreateRole`  
**원인:** AWS Academy는 IAM Role 생성 권한 없음  
**해결:** `aws_iam_role` resource → `data "aws_iam_role" "lab_role"` 으로 변경, LabRole 참조

### 문제 2: CloudWatch Dashboard region 누락
**증상:** `InvalidParameterInput: Should have required property 'region'`  
**원인:** 모든 metric widget에 `region` 필드 필수  
**해결:** 각 widget의 properties에 `region = var.aws_region` 추가

### 문제 3: WordPress 플러그인 설치 시 FTP 요청
**증상:** "Unable to connect to the filesystem"  
**원인:** Apache가 wp-content에 파일 쓰기 권한 없음  
**해결:** EC2 Instance Connect에서 `FS_METHOD = direct` 설정 + 권한 부여

### 문제 4: WP Offload Media S3 연동 실패
**증상:** `Media cannot be offloaded due to missing access keys`  
**원인:** `wp-config.php`의 `serialize(array(...))` 방식이 플러그인에서 인식 안 됨  
**해결:** WordPress Admin UI에서 직접 IAM Role 방식 선택 및 버킷 입력 후 저장

## 11. Cleanup

```bash
terraform destroy
```

Key output:
```
Plan: 0 to add, 0 to change, 25 to destroy.

  Enter a value: yes

aws_cloudwatch_dashboard.wordpress: Destruction complete
aws_autoscaling_group.wordpress: Destruction complete after 3m
aws_lb.wordpress: Destruction complete after 17s
aws_db_instance.wordpress: Destruction complete after 4m24s
aws_s3_bucket.wordpress_media: Destruction complete
...

Destroy complete! Resources: 25 destroyed.
```

Interpretation:
- 25개 리소스 전부 역순으로 정상 삭제 완료
- S3 버킷은 `force_destroy = true`로 파일 있어도 삭제됨
- RDS `skip_final_snapshot = true`로 스냅샷 없이 삭제

## Credential Handling Note

```text
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN은 제출 파일에 넣지 않는다.
TF_VAR_db_master_password도 제출 파일에 넣지 않는다.
terraform.tfvars에는 non-secret 값만 넣는다.
terraform.tfstate는 민감 파일로 취급하고 commit하지 않는다.
```
