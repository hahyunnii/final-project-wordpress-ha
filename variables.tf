variable "aws_region" {
  description = "AWS region used by the AWS Academy lab"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in all AWS resource names"
  type        = string
  default     = "wp-ha-rds"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 characters: lowercase letters, numbers, hyphens."
  }
}

# ── EC2 / ASG ─────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for WordPress web servers"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH. Leave null when SSH is not needed."
  type        = string
  default     = null
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "http_cidr" {
  description = "CIDR block allowed to reach the ALB over HTTP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_ssh" {
  description = "Whether to open SSH/22 on the WordPress EC2 security group"
  type        = bool
  default     = true
}

variable "ssh_cidr" {
  description = "CIDR block allowed to SSH into EC2 instances when enable_ssh is true"
  type        = string
  default     = "0.0.0.0/0"
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated RDS storage in GiB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial RDS database name for WordPress"
  type        = string
  default     = "wordpressdb"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.db_name))
    error_message = "db_name must start with a letter and use only letters, numbers, underscores."
  }
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
  default     = "wpadmin"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,15}$", var.db_master_username))
    error_message = "db_master_username must start with a letter, up to 16 alphanumeric/underscore chars."
  }
}

variable "db_master_password" {
  description = "RDS master password. Set via TF_VAR_db_master_password environment variable — never in tfvars."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_master_password) >= 8 && length(var.db_master_password) <= 41
    error_message = "db_master_password must be 8–41 characters."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.!-]+$", var.db_master_password))
    error_message = "db_master_password may only use letters, numbers, and _+=,.!- characters."
  }
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ deployment for HA (synchronous standby in a second AZ)"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "Number of days RDS automated backups are retained (0 disables backups)"
  type        = number
  default     = 1
}

variable "wordpress_table_prefix" {
  description = "WordPress database table prefix"
  type        = string
  default     = "wp_"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+$", var.wordpress_table_prefix))
    error_message = "wordpress_table_prefix may only contain letters, numbers, and underscores."
  }
}
