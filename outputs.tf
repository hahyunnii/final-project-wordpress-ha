output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.wordpress.id
}

output "instance_public_ip" {
  description = "Public IP address of the WordPress EC2 instance"
  value       = aws_instance.wordpress.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the WordPress EC2 instance"
  value       = aws_instance.wordpress.public_dns
}

output "wordpress_url" {
  description = "WordPress initial setup URL backed by RDS"
  value       = "http://${aws_instance.wordpress.public_dns}/"
}

output "health_check_url" {
  description = "Simple bootstrap health check URL"
  value       = "http://${aws_instance.wordpress.public_dns}/health.html"
}

output "db_check_url" {
  description = "Simple PHP-to-RDS connection check URL"
  value       = "http://${aws_instance.wordpress.public_dns}/db-health.php"
}

output "rds_endpoint" {
  description = "RDS endpoint hostname"
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

output "db_name" {
  description = "RDS database name used by WordPress"
  value       = var.db_name
}

output "db_master_username" {
  description = "RDS master username used by this lab WordPress instance"
  value       = var.db_master_username
}

output "wordpress_table_prefix" {
  description = "WordPress table prefix"
  value       = var.wordpress_table_prefix
}

output "selected_subnet_ids" {
  description = "Default VPC subnets selected for the RDS subnet group"
  value       = local.selected_subnet_ids
}

output "security_group_ids" {
  description = "Security groups created by the lab"
  value = {
    wordpress = aws_security_group.wordpress.id
    rds       = aws_security_group.rds.id
  }
}

output "user_data_log_hint" {
  description = "Where to inspect bootstrap logs if WordPress does not come up"
  value       = "Check /var/log/wordpress-user-data.log on the EC2 instance, or view system log from the EC2 console."
}

output "wordpress_admin_account_note" {
  description = "WordPress administrator account handling"
  value       = "Create the WordPress admin username and password in the browser setup page. Do not put that password in Terraform files."
}
