aws_region    = "us-east-1"
name_prefix   = "wp-final"
instance_type = "t3.micro"

# Networking
http_cidr  = "0.0.0.0/0"
enable_ssh = true
ssh_cidr   = "0.0.0.0/0"
key_name   = null

# RDS
db_instance_class         = "db.t3.micro"
db_allocated_storage      = 20
db_name                   = "wordpressdb"
db_master_username        = "wpadmin"
rds_multi_az              = true
rds_backup_retention_days = 1
wordpress_table_prefix    = "wp_"

# ASG
asg_min_size         = 1
asg_max_size         = 3
asg_desired_capacity = 2

# S3
s3_force_destroy = true

# NOTE: db_master_password는 환경변수로 설정
#   export TF_VAR_db_master_password='Your-Lab-Password-Here'
