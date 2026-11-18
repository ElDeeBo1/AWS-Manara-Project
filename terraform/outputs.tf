output "cloudfront_domain_name" {
  description = "Public URL of the application (open it with https://)."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "alb_dns_name" {
  description = "DNS name of the ALB (reachable only through CloudFront)."
  value       = aws_lb.app.dns_name
}

output "static_bucket_name" {
  description = "S3 bucket that holds the static assets."
  value       = aws_s3_bucket.static.id
}

output "asg_name" {
  description = "Name of the Auto Scaling group."
  value       = aws_autoscaling_group.web.name
}

output "rds_endpoint" {
  description = "RDS endpoint (private, reachable only from the app tier)."
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "Secrets Manager secret that holds the database master credentials."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "sns_topic_arn" {
  description = "SNS topic used for alarm notifications."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "session_manager_hint" {
  description = "How to open a shell on an instance without SSH."
  value       = "aws ssm start-session --target <instance-id> --region ${var.aws_region}"
}
