# Commands Log

## 0. 사전 준비

AWS Academy Learner Lab에 접속한 후 아래 순서로 환경을 설정한다.

**1) AWS Academy → "Start Lab" 클릭 → 상단 점이 🟢으로 바뀌면 준비 완료**

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

**4) 저장소 클론 및 develop 브랜치로 이동**

```bash
git clone https://github.com/mobile-os-dku-cis-mse/06-ec2-rds-with-terraform-hahyunnii.git
cd 06-ec2-rds-with-terraform-hahyunnii
git checkout develop
```

## 1. Preflight

```bash
# AWS Academy temporary credentials 확인
test -n "$AWS_ACCESS_KEY_ID" && echo "AWS_ACCESS_KEY_ID is set"
test -n "$AWS_SECRET_ACCESS_KEY" && echo "AWS_SECRET_ACCESS_KEY is set"
test -n "$AWS_SESSION_TOKEN" && echo "AWS_SESSION_TOKEN is set"

# RDS password는 terraform.tfvars가 아니라 환경 변수로 둔다.
test -n "$TF_VAR_db_master_password" && echo "TF_VAR_db_master_password is set"

# 현재 credentials가 정상인지 확인
aws sts get-caller-identity

# 현재 region 확인
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
- AWS 자격증명 3개(ACCESS_KEY_ID, SECRET_ACCESS_KEY, SESSION_TOKEN)가 모두 설정되어 있음
- TF_VAR_db_master_password 환경변수도 설정되어 있어 terraform.tfvars에 패스워드를 넣지 않아도 됨
- region은 us-east-1으로 설정됨
- Terraform v1.7.5 — 버전 요구사항(>= 1.5.0) 충족

## 2. Init and Format

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
```

Key output:
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

Interpretation:
- AWS provider v5.100.0이 설치되었고 ~> 5.0 제약 조건을 충족함
- terraform fmt가 파일들의 포맷을 정규화함

## 3. Validate and Plan

```bash
terraform validate
terraform plan -out plan.out
terraform show plan.out
```

Key output:
```
Success! The configuration is valid.

Terraform will perform the following actions:

  # aws_autoscaling_group.wordpress will be created
  # aws_autoscaling_policy.scale_in will be created
  # aws_autoscaling_policy.scale_out will be created
  # aws_cloudwatch_metric_alarm.cpu_high will be created
  # aws_cloudwatch_metric_alarm.cpu_low will be created
  # aws_db_instance.wordpress will be created
  # aws_db_subnet_group.wordpress will be created
  # aws_launch_template.wordpress will be created
  # aws_lb.wordpress will be created
  # aws_lb_listener.http will be created
  # aws_lb_target_group.wordpress will be created
  # aws_security_group.alb will be created
  # aws_security_group.rds will be created
  # aws_security_group.wordpress will be created

Plan: 14 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + alb_dns_name        = (known after apply)
  + selected_subnet_ids = [
      + "subnet-0b325a3a157bfff42",
      + "subnet-0907c242196e43f14",
    ]
  + vpc_id              = "vpc-099a13dbc423e5700"

Saved the plan to: plan.out
```

Interpretation:
- 총 14개의 리소스가 생성됨: ALB, Target Group, Listener, ASG, Launch Template, RDS, DB Subnet Group, SG 3개, CloudWatch 알람 2개, ASG 정책 2개
- multi_az = true로 RDS가 두 번째 AZ에 동기식 Standby를 생성함
- publicly_accessible = false — RDS 엔드포인트는 VPC 내부에서만 접근 가능

## 4. Apply

> ⚠️ RDS Multi-AZ 생성으로 인해 **약 10~15분** 소요된다. 완료될 때까지 기다린다.

```bash
terraform apply plan.out
terraform output
terraform output -raw wordpress_url
terraform output -raw health_check_url
terraform output -raw db_check_url
terraform output -raw rds_endpoint
```

Key output:
```
aws_db_subnet_group.wordpress: Creation complete after 1s [id=wp-ha-rds-db-subnets]
aws_security_group.alb: Creation complete after 3s [id=sg-0f5b65c7c67426864]
aws_security_group.wordpress: Creation complete after 3s [id=sg-0d655c34f11996faf]
aws_security_group.rds: Creation complete after 3s [id=sg-01d0cd90b0994177e]
aws_lb.wordpress: Creation complete after 3m3s [id=arn:aws:elasticloadbalancing:us-east-1:980808829165:loadbalancer/app/wp-ha-rds-alb/94c14455c0cbd0ba]
aws_db_instance.wordpress: Creation complete [id=db-A6TLMTZ6PAAVDOCEKLWUFY4EVI]
aws_launch_template.wordpress: Creation complete after 6s [id=lt-090a22a836817a026]
aws_autoscaling_group.wordpress: Creation complete after 1m20s [id=wp-ha-rds-asg]
aws_autoscaling_policy.scale_out: Creation complete [id=wp-ha-rds-scale-out]
aws_autoscaling_policy.scale_in: Creation complete [id=wp-ha-rds-scale-in]
aws_cloudwatch_metric_alarm.cpu_high: Creation complete [id=wp-ha-rds-cpu-high]
aws_cloudwatch_metric_alarm.cpu_low: Creation complete [id=wp-ha-rds-cpu-low]

Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name              = "wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com"
asg_name                  = "wp-ha-rds-asg"
db_check_url              = "http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/db-health.php"
db_master_username        = "wpadmin"
db_name                   = "wordpressdb"
health_check_url          = "http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/health.html"
launch_template_id        = "lt-090a22a836817a026"
rds_endpoint              = "wp-ha-rds-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com"
rds_instance_id           = "wp-ha-rds-mysql"
rds_multi_az              = true
rds_port                  = 3306
security_group_ids        = {
  "alb"       = "sg-0f5b65c7c67426864"
  "rds"       = "sg-01d0cd90b0994177e"
  "wordpress" = "sg-0d655c34f11996faf"
}
selected_subnet_ids       = [
  "subnet-0b325a3a157bfff42",
  "subnet-0907c242196e43f14",
]
vpc_id                    = "vpc-099a13dbc423e5700"
wordpress_url             = "http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/"
```

Interpretation:
- 14개 리소스 모두 생성 완료. RDS Multi-AZ 생성으로 약 10분 소요 — 정상 동작
- ALB DNS: wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com
- RDS 엔드포인트: wp-ha-rds-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com
- ASG가 EC2 2개를 us-east-1a, us-east-1b에 각각 배치

## 5. Verify WordPress EC2 and RDS Connection

> ⚠️ apply 완료 후 EC2 bootstrap에 약 **3~5분** 소요된다. health_check_url이 `ok`를 반환할 때까지 기다린다.

```bash
curl "$(terraform output -raw health_check_url)"
curl "$(terraform output -raw db_check_url)"

aws rds describe-db-instances \
  --db-instance-identifier "$(terraform output -raw rds_instance_id)" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Public:PubliclyAccessible,Engine:Engine}'

# ASG 인스턴스가 두 AZ에 분산 배치됐는지 확인
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=wp-ha-rds-asg" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,PublicIpAddress,Placement.AvailabilityZone]' \
  --output table
```

Key output:
```
# curl health_check_url
ok
name_prefix=wp-ha-rds
instance_id=i-07beca60a583fe60d
availability_zone=us-east-1b
database_host=wp-ha-rds-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com
database_name=wordpressdb

# curl db_check_url
db-ok

# aws rds describe-db-instances
{
    "Status": "available",
    "Endpoint": "wp-ha-rds-mysql.cdc6m8c42ir8.us-east-1.rds.amazonaws.com",
    "Public": false,
    "Engine": "mysql"
}

# ASG 인스턴스 목록
---------------------------------------------------------
|                   DescribeInstances                   |
+---------------------+------------------+--------------+
|  i-0d01ae088fcb0f542|  18.209.221.1    |  us-east-1a  |
|  i-07beca60a583fe60d|  18.212.176.211  |  us-east-1b  |
+---------------------+------------------+--------------+
```

Interpretation:
- `health_check_url`은 EC2 bootstrap이 끝났는지 확인한다. `ok` 응답으로 Apache가 정상 동작하고 user_data 스크립트가 완료됨을 확인
- `db_check_url`은 EC2의 PHP가 RDS MySQL에 접속할 수 있는지 확인한다. `db-ok` 응답으로 PHP → RDS 연결 성공 확인
- RDS `Public` 값이 `false`로 인터넷에서 직접 접근 불가한 보안 경계 확인됨
- EC2 2개가 us-east-1a, us-east-1b에 각각 배치되어 HA 구성 완료

## 6. Verify Security Group Boundary

```bash
# RDS security group은 3306을 EC2 security group source에만 열어야 한다.
aws ec2 describe-security-groups \
  --group-ids "$(terraform output -json security_group_ids | jq -r '.rds')" \
  --query 'SecurityGroups[0].IpPermissions'

# EC2에는 RDS 접속용 IAM role이 필요하지 않다.
# MySQL username/password + security group TCP/3306으로 접속한다.
aws ec2 describe-instances \
  --instance-ids "$(terraform output -raw instance_id)" \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

Key output:
```json
[
    {
        "FromPort": 3306,
        "IpProtocol": "tcp",
        "IpRanges": [],
        "Ipv6Ranges": [],
        "PrefixListIds": [],
        "ToPort": 3306,
        "UserIdGroupPairs": [
            {
                "Description": "MySQL from WordPress EC2 instances",
                "GroupId": "sg-0d655c34f11996faf",
                "UserId": "980808829165"
            }
        ]
    }
]
```

Interpretation:
- RDS SG의 3306 포트 인그레스 규칙: `IpRanges`가 비어있고(0.0.0.0/0 없음), `UserIdGroupPairs`에 WordPress EC2 SG(`sg-0d655c34f11996faf`)만 허용
- 이 설정이 핵심 보안 경계: 인터넷에서 RDS로 직접 접근 불가, EC2 인스턴스를 통해서만 DB 접근 가능
- EC2 SG(`sg-0d655c34f11996faf`)는 ALB SG(`sg-0f5b65c7c67426864`)에서 오는 포트 80만 허용 — EC2 직접 접근 불가

## 7. Complete WordPress Setup

```text
terraform output -raw wordpress_url 로 나온 주소를 브라우저에서 연다.
http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/

WordPress site title, admin username, admin password, email을 입력한다.
이때 생성되는 WordPress tables는 EC2 로컬 MariaDB가 아니라 RDS MySQL에 저장된다.
```

Key output:
- WordPress 설치 완료: 사이트 "WordPress HA Lab" 정상 접속 확인
- 브라우저에서 Blog 화면 및 "Hello world!" 포스트 출력 확인
- WordPress URL: http://wp-ha-rds-alb-2082097614.us-east-1.elb.amazonaws.com/

Interpretation:
- WordPress tables(wp_posts, wp_users, wp_options 등)이 RDS MySQL(wordpressdb)에 저장됨
- EC2 로컬 디스크에는 WordPress PHP 파일(/var/www/html/)과 Apache 설정만 존재
- 2개의 EC2(i-0d01ae088fcb0f542, i-07beca60a583fe60d)가 동일한 RDS를 공유 — split-brain 없음
- WP_HOME / WP_SITEURL이 ALB DNS로 설정되어 어느 EC2에서 응답해도 URL이 올바르게 생성됨

## 8. Troubleshooting

### 문제 1: terraform validate 오류 — bash 변수 이스케이프

**증상:**
```
│ Error: Error in function call
│   on main.tf line 236, in resource "aws_launch_template" "wordpress":
│  236:   user_data = base64encode(templatefile("${path.module}/user-data.sh", {
│ Call to function "templatefile" failed: ./user-data.sh:40,38-39: Invalid character
```

**원인:**
Terraform의 `templatefile()`은 `${...}`를 template 변수로 해석한다.
`user-data.sh` 내의 bash 변수(`${LAMP_PACKAGES[@]}`, `${METADATA_TOKEN}` 등)가 충돌 발생.

**해결:**
`user-data.sh`의 bash 변수를 모두 `$${...}`로 이스케이프한다.
(예: `${LAMP_PACKAGES[@]}` → `$${LAMP_PACKAGES[@]}`)

```bash
# 수정 후 validate 재실행
terraform validate
# → Success! The configuration is valid.

# 수정 사항 커밋 및 push
git add user-data.sh
git commit -m "fix: escape bash variables in user-data.sh for Terraform templatefile"
git push origin develop
```

---

### 문제 2: RDS 생성 중 터미널 세션 끊김

**증상:**
apply 실행 중 RDS Multi-AZ 생성 단계(약 8분 경과)에서 터미널 세션이 끊김.

**원인:**
AWS Academy 환경의 웹 터미널 세션 타임아웃.

**해결:**
새 터미널을 열어 환경변수를 재설정하고, AWS에서 실제 생성된 리소스와 terraform state를 동기화한 후 재실행.

```bash
# 1. 새 터미널에서 환경변수 재설정
cd ~/06-ec2-rds-with-terraform-hahyunnii
git checkout develop
export TF_VAR_db_master_password='WpLabPass123!'

# 2. RDS가 실제로 생성 완료됐는지 확인
aws rds describe-db-instances \
  --db-instance-identifier wp-ha-rds-mysql \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ}'

# 3. terraform state에 어떤 리소스가 등록됐는지 확인
terraform state list

# 4. state에 RDS가 없지만 AWS에는 이미 존재하므로 import로 등록
terraform import aws_db_instance.wordpress wp-ha-rds-mysql

# 5. 나머지 리소스 생성을 위해 plan 재실행 후 apply
terraform plan -out plan.out
terraform apply plan.out
```

Key output:
```
# RDS 상태 확인
{
    "Status": "available",
    "MultiAZ": true
}

# terraform state list — aws_db_instance.wordpress 없음 확인
aws_db_subnet_group.wordpress
aws_lb.wordpress
aws_lb_listener.http
aws_lb_target_group.wordpress
aws_security_group.alb
aws_security_group.rds
aws_security_group.wordpress

# import 성공
Import successful!

# 재실행 plan — 나머지 6개 리소스만 생성
Plan: 6 to add, 1 to change, 0 to destroy.

Apply complete! Resources: 6 added, 1 changed, 0 destroyed.
```

---

### 문제 3: plan.out 재사용 오류

**증상:**
```
│ Error: Saved plan is stale
│ The given plan file can no longer be applied because the state was changed
│ by another operation after the plan was created.
```

**원인:**
이전 apply 도중 state가 변경되어 저장된 plan.out이 유효하지 않음.

**해결:**
plan을 새로 생성한 후 apply한다.
```bash
terraform plan -out plan.out
terraform apply plan.out
```

## 9. Cleanup

```bash
terraform destroy
```

Key output:
```
Plan: 0 to add, 0 to change, 14 to destroy.

  Enter a value: yes

aws_cloudwatch_metric_alarm.cpu_high: Destruction complete after 1s
aws_cloudwatch_metric_alarm.cpu_low: Destruction complete after 1s
aws_autoscaling_policy.scale_out: Destruction complete after 0s
aws_autoscaling_policy.scale_in: Destruction complete after 0s
aws_autoscaling_group.wordpress: Destruction complete after 6m3s
aws_lb_target_group.wordpress: Destruction complete after 0s
aws_launch_template.wordpress: Destruction complete after 1s
aws_lb.wordpress: Destruction complete after 17s
aws_db_instance.wordpress: Destruction complete after 4m24s
aws_db_subnet_group.wordpress: Destruction complete after 0s
aws_security_group.rds: Destruction complete after 1s
aws_security_group.wordpress: Destruction complete after 1s
aws_security_group.alb: Destruction complete after 1s

Destroy complete! Resources: 14 destroyed.
```

Interpretation:
- 14개 리소스 전부 역순으로 정상 삭제 완료
- ASG 삭제 시 EC2 인스턴스를 ALB에서 drain 후 종료 (약 6분 소요 — 정상)
- RDS 삭제 약 4분 24초 소요. skip_final_snapshot = true로 스냅샷 없이 삭제
- AWS Console에서 EC2, RDS, ALB, ASG 모두 삭제 확인 — 잔여 리소스 없음

## Credential Handling Note

```text
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN은 제출 파일에 넣지 않는다.
TF_VAR_db_master_password도 제출 파일에 넣지 않는다.
terraform.tfvars에는 non-secret 값만 넣는다.
terraform.tfstate는 민감 파일로 취급하고 commit하지 않는다.
```
