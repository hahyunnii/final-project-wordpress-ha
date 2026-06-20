# ── ALB ───────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "ALB DNS name — WordPress site URL"
  value       = aws_lb.wordpress.dns_name
}

output "wordpress_url" {
  description = "WordPress site URL"
  value       = "http://${aws_lb.wordpress.dns_name}/"
}

output "health_check_url" {
  description = "ALB health check endpoint"
  value       = "http://${aws_lb.wordpress.dns_name}/health.html"
}

output "db_check_url" {
  description = "PHP → RDS connectivity check"
  value       = "http://${aws_lb.wordpress.dns_name}/db-health.php"
}

# ── ASG ───────────────────────────────────────────────────────────────────────

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.wordpress.name
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.wordpress.id
}

# ── RDS ───────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS MySQL endpoint (VPC-internal)"
  value       = aws_db_instance.wordpress.address
}

output "rds_instance_id" {
  description = "RDS DB instance identifier"
  value       = aws_db_instance.wordpress.identifier
}

output "rds_multi_az" {
  description = "Whether RDS Multi-AZ is enabled"
  value       = aws_db_instance.wordpress.multi_az
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.wordpress.port
}

# ── S3 ────────────────────────────────────────────────────────────────────────

output "s3_bucket_name" {
  description = "S3 bucket for WordPress media offload"
  value       = aws_s3_bucket.wordpress_media.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.wordpress_media.arn
}

output "s3_bucket_url" {
  description = "S3 bucket public URL base"
  value       = "https://${aws_s3_bucket.wordpress_media.bucket_regional_domain_name}"
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "ec2_iam_role_name" {
  description = "IAM role attached to EC2 instances for S3 access (AWS Academy LabRole)"
  value       = data.aws_iam_role.lab_role.name
}

# ── Networking ────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.default.id
}

output "selected_subnet_ids" {
  description = "Subnets used (one per AZ)"
  value       = local.selected_subnet_ids
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb       = aws_security_group.alb.id
    wordpress = aws_security_group.wordpress.id
    rds       = aws_security_group.rds.id
  }
}

# ── CloudWatch ────────────────────────────────────────────────────────────────

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.wordpress.dashboard_name}"
}

# ── Hints ─────────────────────────────────────────────────────────────────────

output "s3_offload_setup_hint" {
  description = "WordPress 설치 후 S3 Offload Media 플러그인 설정 방법"
  value       = "WordPress Admin → Plugins → WP Offload Media Lite → Bucket: ${aws_s3_bucket.wordpress_media.id} (IAM Role로 자동 인증)"
}
