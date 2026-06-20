# ──────────────────────────────────────────────────────────────────────────────
# DATA SOURCES  — reuse the default VPC and discover subnets across all AZs
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

# Latest Amazon Linux 2023 AMI from AWS-managed SSM parameter.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ──────────────────────────────────────────────────────────────────────────────
# LOCALS  — pick two AZs for HA; select one subnet per AZ
# ──────────────────────────────────────────────────────────────────────────────

locals {
  subnets_by_az = {
    for _, subnet in data.aws_subnet.default_vpc :
    subnet.availability_zone => subnet.id...
  }

  # Always use at least 2 AZs for HA (ALB + RDS Multi-AZ requirement)
  selected_azs = slice(sort(keys(local.subnets_by_az)), 0, min(2, length(keys(local.subnets_by_az))))

  selected_subnet_ids = [
    for az in local.selected_azs : sort(local.subnets_by_az[az])[0]
  ]

  common_tags = {
    Course = "cloud-computing-aws"
    Lab    = "week-12-wordpress-ec2-rds-ha"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ──────────────────────────────────────────────────────────────────────────────

# ALB Security Group — accepts public HTTP/HTTPS
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow HTTP from the internet to the Application Load Balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-alb-sg" })
}

# WordPress EC2 Security Group — accepts HTTP only from ALB, optional SSH
resource "aws_security_group" "wordpress" {
  name        = "${var.name_prefix}-wordpress-sg"
  description = "Allow HTTP from ALB and optional SSH for troubleshooting"
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
      description = "Optional SSH for troubleshooting"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    description = "Allow outbound for package downloads and RDS access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-wordpress-sg" })
}

# RDS Security Group — accepts MySQL only from WordPress EC2 SG
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow MySQL from WordPress EC2 security group only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from WordPress EC2 instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-rds-sg" })
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS  — MySQL with Multi-AZ for HA database tier
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

  # HA: Multi-AZ creates a synchronous standby replica in a second AZ.
  # Automatic failover promotes the standby if the primary fails.
  multi_az = var.rds_multi_az

  publicly_accessible     = false
  storage_type            = "gp2"
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = var.rds_backup_retention_days
  apply_immediately       = true

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-mysql" })
}

# ──────────────────────────────────────────────────────────────────────────────
# APPLICATION LOAD BALANCER
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
# LAUNCH TEMPLATE  — used by the Auto Scaling Group
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "wordpress" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  key_name      = var.key_name

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
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.name_prefix}-wordpress" })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# AUTO SCALING GROUP  — HA web tier across 2 AZs
# ──────────────────────────────────────────────────────────────────────────────

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
# AUTO SCALING POLICIES  — scale out when CPU > 70%, scale in when CPU < 30%
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.name_prefix}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out when average CPU > 70% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "${var.name_prefix}-scale-in"
  autoscaling_group_name = aws_autoscaling_group.wordpress.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
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
  alarm_description   = "Scale in when average CPU < 30% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress.name
  }
}
