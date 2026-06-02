# Week 10B Bridge Lab: WordPress on One EC2 Instance with RDS

This lab keeps the WordPress installation flow from `week-09-prelab-wordpress-terraform`, but moves the database from local MariaDB on the EC2 instance to RDS MySQL.
It is intended as a bridge between the `week-10-lab-cloudwatch-autoscaling` ALB/ASG lab and the `week-11-rds` migration lab.

## Learning Objectives

- Create one WordPress EC2 instance and one RDS MySQL instance with Terraform.
- Allow browser traffic to the EC2 instance over public HTTP `80`.
- Keep RDS private and allow MySQL `3306` only from the WordPress EC2 security group.
- Replace the week-09 local MariaDB bootstrap step with an RDS connection.
- Verify that WordPress tables created during initial setup are stored in RDS.
- Understand why the next migration lab moves an existing local WordPress database into RDS.

## Created Resources

- 1 EC2 WordPress instance
- 1 RDS MySQL DB instance
- 1 RDS DB subnet group
- 1 WordPress EC2 security group
- 1 RDS security group

## Architecture

Traffic flow:

- Browser -> EC2 public HTTP `80`
- EC2 WordPress -> RDS private MySQL `3306`

The RDS security group allows MySQL access only from the WordPress EC2 security group.
The RDS instance is created with `publicly_accessible = false`.

## Difference From Week 09

Week 09 installs Apache, PHP, MariaDB, and WordPress on a single EC2 instance.
This lab still installs Apache, PHP, and WordPress on EC2, but it does not run the database server on EC2.
Instead, Terraform creates an RDS MySQL instance and the EC2 bootstrap script configures `wp-config.php` to use the RDS endpoint.

The default RDS database name is `wordpressdb`.
Unlike the week-09 local database name `wordpress-db`, this lab avoids hyphens because RDS MySQL `db_name` is easier to handle with letters, numbers, and underscores only.

## RDS Settings Added After Week 09

Week 09 only needs one subnet and one EC2 security group because the database runs inside the same EC2 instance.
This lab adds several RDS-specific settings because the database becomes a separate managed resource inside the VPC.

### Default VPC Subnet Selection

RDS uses a DB subnet group instead of a single EC2 subnet.
The Terraform code reads the default VPC subnets, groups them by Availability Zone, and selects one subnet from two Availability Zones:

- `data.aws_subnet.default_vpc`: loads details for each default VPC subnet
- `local.subnets_by_az`: groups subnet IDs by Availability Zone
- `local.selected_subnet_ids`: chooses the subnets used by RDS
- `local.selected_web_subnet_id`: chooses one of those subnets for the WordPress EC2 instance

Beginner takeaway: EC2 can launch in one subnet, but RDS needs a DB subnet group so AWS knows which VPC subnets the database service may use.

### DB Subnet Group

`aws_db_subnet_group.wordpress` is new in this lab.
It connects the RDS instance to the selected default VPC subnets:

```hcl
resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = local.selected_subnet_ids
}
```

This does not make RDS public.
It only tells RDS where it can place database network interfaces inside the VPC.

### RDS Security Group

Week 09 opens HTTP directly to the EC2 instance.
This lab keeps that EC2 HTTP rule, then adds a separate RDS security group:

```hcl
resource "aws_security_group" "rds" {
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }
}
```

The important part is `security_groups = [aws_security_group.wordpress.id]`.
It means MySQL is reachable only from network interfaces that use the WordPress EC2 security group.
The RDS MySQL port is not opened to `0.0.0.0/0`.

### RDS DB Instance

`aws_db_instance.wordpress` creates the managed MySQL database.
These settings are new compared with Week 09:

| Setting | Value in this lab | Why it exists |
| --- | --- | --- |
| `engine` | `mysql` | Runs MySQL as a managed RDS engine |
| `instance_class` | `var.db_instance_class` | Chooses DB compute size, default `db.t3.micro` |
| `allocated_storage` | `var.db_allocated_storage` | Chooses DB storage size, default 20 GiB |
| `db_name` | `var.db_name` | Creates the initial WordPress database |
| `username` / `password` | Terraform variables | Creates the DB login WordPress uses |
| `db_subnet_group_name` | `aws_db_subnet_group.wordpress.name` | Places RDS in selected VPC subnets |
| `vpc_security_group_ids` | RDS security group | Controls who can reach MySQL `3306` |
| `publicly_accessible` | `false` | Keeps the database off the public internet |
| `skip_final_snapshot` | `true` | Makes lab cleanup simpler; not a production default |
| `backup_retention_period` | `0` | Disables automated backups for a short lab |
| `deletion_protection` | `false` | Allows `terraform destroy` to remove the DB |

The last three settings are lab conveniences.
For a real database, you would normally keep backups, consider final snapshots, and use deletion protection.

### WordPress EC2 Bootstrap Changes

Week 09 installs and starts `mariadb105-server` on the EC2 instance.
This lab does not run a database server on EC2.
Instead, `user_data` receives RDS connection values from Terraform:

```hcl
user_data = templatefile("${path.module}/user-data.sh", {
  db_name     = var.db_name
  db_username = var.db_master_username
  db_password = var.db_master_password
  db_host     = aws_db_instance.wordpress.address
  db_port     = aws_db_instance.wordpress.port
})
```

The bootstrap script then:

- installs Apache, PHP, WordPress, and a MySQL/MariaDB client
- waits until RDS accepts a `SELECT 1` query
- writes the RDS endpoint into `wp-config.php`
- creates `/db-health.php` so students can verify PHP-to-RDS connectivity

### New Variables and Outputs

The RDS variables are also new compared with Week 09:

- `db_instance_class`
- `db_allocated_storage`
- `db_name`
- `db_master_username`
- `db_master_password`

The RDS-related outputs help students verify the deployment:

- `db_check_url`
- `rds_endpoint`
- `rds_port`
- `rds_instance_id`
- `db_name`
- `db_master_username`
- `selected_subnet_ids`
- `security_group_ids`

## Password Handling

Do not put the RDS password in `terraform.tfvars`.
Set it as an environment variable before running Terraform:

```bash
export TF_VAR_db_master_password='Use-A-Lab-Only-Password-Here'
```

Note: Terraform still stores the RDS password in Terraform state as a sensitive value.
This lab's `.gitignore` excludes state files, but the local state file should still be treated as sensitive.

## Quick Start

```bash
cd eng/toy-examples/week-10b-wordpress-ec2-rds

# AWS Academy Learner Lab temporary credentials
export AWS_ACCESS_KEY_ID="<access-key-id>"
export AWS_SECRET_ACCESS_KEY="<secret-access-key>"
export AWS_SESSION_TOKEN="<session-token>"

# Keep the RDS password out of terraform.tfvars.
export TF_VAR_db_master_password='Use-A-Lab-Only-Password-Here'

cp terraform.tfvars.example terraform.tfvars

terraform init
terraform fmt
terraform validate
terraform plan -out plan.out
terraform apply plan.out

terraform output
curl "$(terraform output -raw health_check_url)"
curl "$(terraform output -raw db_check_url)"
```

Open the WordPress initial setup page in a browser:

```bash
terraform output -raw wordpress_url
```

## Verification Points

Check the RDS instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$(terraform output -raw rds_instance_id)" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Public:PubliclyAccessible,Engine:Engine}'
```

The RDS security group should not allow `0.0.0.0/0` on MySQL `3306`.
It should use the WordPress EC2 security group as the source.

```bash
aws ec2 describe-security-groups \
  --group-ids "$(terraform output -json security_group_ids | jq -r '.rds')" \
  --query 'SecurityGroups[0].IpPermissions'
```

No EC2 IAM role is required for this RDS connection.
This beginner lab uses MySQL username/password authentication plus security group rules.

## AWS Academy Notes

- Keep AWS credentials in environment variables only.
- `AWS_SESSION_TOKEN` is required in AWS Academy Learner Lab.
- RDS creation can take longer than EC2 creation.
- Start small with `db.t3.micro` and 20 GiB storage.
- RDS can incur cost, so run `terraform destroy` after the lab.
- `skip_final_snapshot = true` means the database is deleted when the lab is destroyed.

## Cleanup

```bash
terraform destroy
```

After cleanup, check the AWS Console and confirm that no EC2 or RDS instances from this lab remain.
