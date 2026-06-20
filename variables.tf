variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in all AWS resource names"
  type        = string
  default     = "wp-final"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 characters: lowercase letters, numbers, hyphens."
  }
}

# ── EC2 / ASG ─────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair name for SSH. null = SSH disabled."
  type        = string
  default     = null
}

variable "asg_min_size" {
  description = "ASG minimum instance count"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "ASG maximum instance count"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "ASG desired instance count"
  type        = number
  default     = 2
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "http_cidr" {
  description = "CIDR allowed to reach ALB over HTTP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_ssh" {
  description = "Open SSH/22 on the WordPress EC2 security group"
  type        = bool
  default     = true
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH into EC2"
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
  description = "RDS storage in GiB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpressdb"
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
  default     = "wpadmin"
}

variable "db_master_password" {
  description = "RDS master password. Set via TF_VAR_db_master_password — never in tfvars."
  type        = string
  sensitive   = true
}

variable "rds_multi_az" {
  description = "Enable RDS Multi-AZ"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "RDS automated backup retention days"
  type        = number
  default     = 1
}

variable "wordpress_table_prefix" {
  description = "WordPress DB table prefix"
  type        = string
  default     = "wp_"
}

# ── S3 ────────────────────────────────────────────────────────────────────────

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete non-empty S3 bucket"
  type        = bool
  default     = true
}
