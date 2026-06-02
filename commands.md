# Commands Log Template

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

Interpretation:

## 2. Init and Format

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
```

Key output:

Interpretation:

## 3. Validate and Plan

```bash
terraform validate
terraform plan -out plan.out
terraform show plan.out
```

Key output:

Interpretation:

## 4. Apply

```bash
terraform apply plan.out
terraform output
terraform output -raw wordpress_url
terraform output -raw health_check_url
terraform output -raw db_check_url
terraform output -raw rds_endpoint
```

Key output:

Interpretation:

## 5. Verify WordPress EC2 and RDS Connection

```bash
curl "$(terraform output -raw health_check_url)"
curl "$(terraform output -raw db_check_url)"

aws rds describe-db-instances \
  --db-instance-identifier "$(terraform output -raw rds_instance_id)" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Public:PubliclyAccessible,Engine:Engine}'
```

Key output:

Interpretation:
- `health_check_url`은 EC2 bootstrap이 끝났는지 확인한다.
- `db_check_url`은 EC2의 PHP가 RDS MySQL에 접속할 수 있는지 확인한다.
- RDS `Public` 값은 `false`여야 한다.

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

Interpretation:

## 7. Complete WordPress Setup

```text
terraform output -raw wordpress_url 로 나온 주소를 브라우저에서 연다.
WordPress site title, admin username, admin password, email을 입력한다.
이때 생성되는 WordPress tables는 EC2 로컬 MariaDB가 아니라 RDS MySQL에 저장된다.
```

Key output:

Interpretation:

## 8. Troubleshooting

```bash
# EC2 콘솔의 Instance settings -> Get system log에서 user_data 로그를 확인할 수 있다.
# SSH를 켠 경우에는 인스턴스 내부 로그도 확인한다.
sudo tail -n 100 /var/log/wordpress-user-data.log
sudo systemctl status httpd
sudo systemctl status php-fpm
cat /home/ec2-user/rds-connection.txt

# RDS 상태 확인
aws rds describe-db-instances \
  --db-instance-identifier "$(terraform output -raw rds_instance_id)"
```

Key output:

Interpretation:

## 9. Cleanup

```bash
terraform destroy
```

Key output:

Interpretation:

## Credential Handling Note

```text
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN은 제출 파일에 넣지 않는다.
TF_VAR_db_master_password도 제출 파일에 넣지 않는다.
terraform.tfvars에는 non-secret 값만 넣는다.
terraform.tfstate는 민감 파일로 취급하고 commit하지 않는다.
```
