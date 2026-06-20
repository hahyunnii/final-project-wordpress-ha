# ──────────────────────────────────────────────────────────────────────────────
# DATA SOURCES
# ──────────────────────────────────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default_vpc" {
  for_each = toset(data.aws_subnets.default_vpc.ids)
  id       = each.value
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────────────────────────────────────
# LOCALS
# ──────────────────────────────────────────────────────────────────────────────

locals {
  subnets_by_az = {
    for _, subnet in data.aws_subnet.default_vpc :
    subnet.availability_zone => subnet.id...
  }

  selected_azs = slice(sort(keys(local.subnets_by_az)), 0, min(2, length(keys(local.subnets_by_az))))

  selected_subnet_ids = [
    for az in local.selected_azs : sort(local.subnets_by_az[az])[0]
  ]

  common_tags = {
    Course  = "cloud-computing-aws"
    Project = "final-wordpress-ha-s3"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 — WordPress 미디어 파일 저장소
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "wordpress_media" {
  bucket        = "${var.name_prefix}-media-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-media" })
}

resource "aws_s3_bucket_public_access_block" "wordpress_media" {
  bucket = aws_s3_bucket.wordpress_media.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_ownership_controls" "wordpress_media" {
  bucket = aws_s3_bucket.wordpress_media.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "wordpress_media" {
  bucket = aws_s3_bucket.wordpress_media.id

  depends_on = [
    aws_s3_bucket_public_access_block.wordpress_media,
    aws_s3_bucket_ownership_controls.wordpress_media,
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.wordpress_media.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_cors_configuration" "wordpress_media" {
  bucket = aws_s3_bucket.wordpress_media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3600
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM — EC2가 S3에 접근하기 위한 Role
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "wordpress_ec2" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-ec2-role" })
}

resource "aws_iam_role_policy" "wordpress_s3" {
  name = "${var.name_prefix}-s3-policy"
  role = aws_iam_role.wordpress_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObjectAcl",
        ]
        Resource = [
          aws_s3_bucket.wordpress_media.arn,
          "${aws_s3_bucket.wordpress_media.arn}/*",
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "wordpress_ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.wordpress_ec2.name

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-ec2-profile" })
}

# ──────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_security_group" "wordpress" {
  name        = "${var.name_prefix}-wordpress-sg"
  description = "Allow HTTP from ALB and optional SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH for troubleshooting"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-wordpress-sg" })
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow MySQL from WordPress EC2 SG only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from WordPress EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-rds-sg" })
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS — MySQL Multi-AZ
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = local.selected_subnet_ids

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-db-subnets" })
}

resource "aws_db_instance" "wordpress" {
  identifier        = "${var.name_prefix}-mysql"
  allocated_storage = var.db_allocated_storage
  db_name           = var.db_name
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = var.db_instance_class
  username          = var.db_master_username
  password          = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = var.rds_multi_az
  publicly_accessible     = false
  storage_type            = "gp2"
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = var.rds_backup_retention_days
  apply_immediately       = true

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-mysql" })
}

# ──────────────────────────────────────────────────────────────────────────────
# ALB
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "wordpress" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.selected_subnet_ids

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "wordpress" {
  name     = "${var.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/health.html"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# LAUNCH TEMPLATE + ASG
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress_ec2.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.wordpress.id]
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    name_prefix            = var.name_prefix
    db_name                = var.db_name
    db_username            = var.db_master_username
    db_password            = var.db_master_password
    db_host                = aws_db_instance.wordpress.address
    db_port                = aws_db_instance.wordpress.port
    wordpress_table_prefix = var.wordpress_table_prefix
    alb_dns_name           = aws_lb.wordpress.dns_name
    s3_bucket              = aws_s3_bucket.wordpress_media.id
    aws_region             = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.name_prefix}-wordpress" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  name                = "${var.name_prefix}-asg"
  vpc_zone_identifier = local.selected_subnet_ids

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  target_group_arns         = [aws_lb_target_group.wordpress.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { Name = "${var.name_prefix}-wordpress" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# AUTO SCALING POLICIES
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.name_prefix}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.name_prefix}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

# ──────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH — EC2 CPU Alarms
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when CPU > 70% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.name_prefix}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in when CPU < 30% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH — RDS Alarms
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 120
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80% — investigate slow queries"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.name_prefix}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2 GiB in bytes
  alarm_description   = "RDS free storage < 2 GiB"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.wordpress.identifier
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# CLOUDWATCH — Dashboard
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "wordpress" {
  dashboard_name = "${var.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# WordPress HA + S3 — Final Project Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization (ASG)"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.wordpress.name]
          ]
          annotations = {
            horizontal = [
              { label = "Scale-out threshold", value = 70, color = "#ff6961" },
              { label = "Scale-in threshold", value = 30, color = "#77dd77" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count & Response Time"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.wordpress.arn_suffix, { stat = "Sum", label = "RequestCount" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.wordpress.arn_suffix, { stat = "Average", label = "ResponseTime (avg)", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ASG Instance Count"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", aws_autoscaling_group.wordpress.name, { label = "Desired" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.wordpress.name, { label = "InService" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU & DB Connections"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.wordpress.identifier, { stat = "Average", label = "CPU %" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.wordpress.identifier, { stat = "Average", label = "Connections", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "RDS Free Storage Space"
          view   = "timeSeries"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.wordpress.identifier]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB Healthy Host Count"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.wordpress.arn_suffix, "LoadBalancer", aws_lb.wordpress.arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 19
        width  = 24
        height = 6
        properties = {
          title  = "S3 Bucket — Request Metrics"
          view   = "timeSeries"
          period = 300
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.wordpress_media.id, "StorageType", "AllStorageTypes", { stat = "Average", label = "Object Count" }],
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.wordpress_media.id, "StorageType", "StandardStorage", { stat = "Average", label = "Bucket Size (bytes)", yAxis = "right" }]
          ]
        }
      }
    ]
  })
}
