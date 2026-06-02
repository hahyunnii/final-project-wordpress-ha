# AWS Academy labs usually provide a default VPC. Reusing it keeps this bridge lab focused on EC2 -> RDS wiring.
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

# Latest Amazon Linux 2023 AMI from the AWS-managed public SSM parameter namespace.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  subnets_by_az = {
    for _, subnet in data.aws_subnet.default_vpc :
    subnet.availability_zone => subnet.id...
  }

  selected_azs = slice(sort(keys(local.subnets_by_az)), 0, 2)
  selected_subnet_ids = [
    for az in local.selected_azs : sort(local.subnets_by_az[az])[0]
  ]
  selected_web_subnet_id = local.selected_subnet_ids[0]

  common_tags = {
    Course = "cloud-computing-aws"
    Lab    = "week-10b-wordpress-ec2-rds"
  }
}

resource "aws_security_group" "wordpress" {
  name        = "${var.name_prefix}-wordpress-sg"
  description = "Allow HTTP access to the WordPress EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow public HTTP access for the WordPress setup page"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []

    content {
      description = "Optional SSH access for troubleshooting"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_cidr]
    }
  }

  egress {
    description = "Allow outbound package downloads and RDS access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-wordpress-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow MySQL access only from the WordPress EC2 security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow MySQL from the WordPress EC2 instance"
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

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rds-sg"
  })
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = local.selected_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-db-subnets"
  })
}

resource "aws_db_instance" "wordpress" {
  identifier             = "${var.name_prefix}-mysql"
  allocated_storage      = var.db_allocated_storage
  db_name                = var.db_name
  engine                 = "mysql"
  instance_class         = var.db_instance_class
  username               = var.db_master_username
  password               = var.db_master_password
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible     = false
  storage_type            = "gp2"
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-mysql"
  })
}

resource "aws_instance" "wordpress" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = local.selected_web_subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.wordpress.id]
  key_name                    = var.key_name

  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh", {
    name_prefix            = var.name_prefix
    db_name                = var.db_name
    db_username            = var.db_master_username
    db_password            = var.db_master_password
    db_host                = aws_db_instance.wordpress.address
    db_port                = aws_db_instance.wordpress.port
    wordpress_table_prefix = var.wordpress_table_prefix
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-wordpress"
  })
}
