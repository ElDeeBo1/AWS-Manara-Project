# Changelog

## [1.0.0] - 2026-11-18

### Added
- VPC `10.0.0.0/16` with public, app and DB subnets across two Availability Zones
- Internet Gateway, one NAT Gateway per AZ, route tables and NACLs
- Application Load Balancer with target group, health checks and a listener rule
- AWS WAF web ACL (managed OWASP-oriented rule groups and a rate limit) on the ALB
- EC2 Launch Template and Auto Scaling group with target tracking and step scaling
- RDS Multi-AZ (MySQL or PostgreSQL) with credentials in Secrets Manager
- CloudFront with ALB and S3 origins, Route 53 health check and optional alias record
- Systems Manager Session Manager access (no SSH, no bastion)
- CloudWatch dashboard and alarms with SNS notifications
