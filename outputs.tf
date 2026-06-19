# ── ALB ───────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer — use this as the WordPress URL"
  value       = aws_lb.wordpress.dns_name
}

output "wordpress_url" {
  description = "WordPress site URL via the ALB"
  value       = "http://${aws_lb.wordpress.dns_name}/"
}

output "health_check_url" {
  description = "ALB health check endpoint"
  value       = "http://${aws_lb.wordpress.dns_name}/health.html"
}

output "db_check_url" {
  description = "PHP-to-RDS connectivity check endpoint"
  value       = "http://${aws_lb.wordpress.dns_name}/db-health.php"
}

# ── ASG ───────────────────────────────────────────────────────────────────────

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.wordpress.name
}

output "launch_template_id" {
  description = "Launch Template ID used by the ASG"
  value       = aws_launch_template.wordpress.id
}

# ── RDS ───────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS MySQL endpoint address (private, VPC-only)"
  value       = aws_db_instance.wordpress.address
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.wordpress.port
}

output "rds_instance_id" {
  description = "RDS DB instance identifier"
  value       = aws_db_instance.wordpress.identifier
}

output "rds_multi_az" {
  description = "Whether RDS Multi-AZ is enabled"
  value       = aws_db_instance.wordpress.multi_az
}

output "db_name" {
  description = "WordPress database name on RDS"
  value       = var.db_name
}

output "db_master_username" {
  description = "RDS master username"
  value       = var.db_master_username
}

# ── Networking ────────────────────────────────────────────────────────────────

output "selected_subnet_ids" {
  description = "Subnets used by ALB, ASG, and RDS (one per AZ)"
  value       = local.selected_subnet_ids
}

output "security_group_ids" {
  description = "Security group IDs for ALB, WordPress EC2, and RDS"
  value = {
    alb       = aws_security_group.alb.id
    wordpress = aws_security_group.wordpress.id
    rds       = aws_security_group.rds.id
  }
}

output "vpc_id" {
  description = "VPC ID used by this deployment"
  value       = data.aws_vpc.default.id
}

# ── Hints ─────────────────────────────────────────────────────────────────────

output "user_data_log_hint" {
  description = "Where to find bootstrap logs on any EC2 instance"
  value       = "sudo tail -f /var/log/wordpress-user-data.log  (SSH into any ASG instance)"
}

output "asg_instance_refresh_hint" {
  description = "Command to rolling-replace ASG instances after a config change"
  value       = "aws autoscaling start-instance-refresh --auto-scaling-group-name ${aws_autoscaling_group.wordpress.name}"
}
