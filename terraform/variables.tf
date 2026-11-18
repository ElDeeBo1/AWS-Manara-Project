variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources."
  type        = string
  default     = "scalable-web"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

# ---------- Network ----------
variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# ---------- Compute ----------
variable "instance_type" {
  description = "EC2 instance type for the web tier."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling group."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Initial desired number of instances."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling group."
  type        = number
  default     = 6
}

variable "cpu_target_value" {
  description = "Target average CPU (%) for the target tracking policy."
  type        = number
  default     = 50
}

variable "requests_per_target" {
  description = "Target ALB requests per instance for the second target tracking policy."
  type        = number
  default     = 500
}

# ---------- Database ----------
variable "db_engine" {
  description = "Database engine: mysql or postgres."
  type        = string
  default     = "mysql"

  validation {
    condition     = contains(["mysql", "postgres"], var.db_engine)
    error_message = "db_engine must be either \"mysql\" or \"postgres\"."
  }
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username. The password is generated and stored in AWS Secrets Manager."
  type        = string
  default     = "dbadmin"
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on the RDS instance (set true for production)."
  type        = bool
  default     = false
}

# ---------- Edge / DNS ----------
variable "domain_name" {
  description = "Optional custom domain (for example www.example.com). Leave empty to use the CloudFront domain."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID that contains domain_name. Required only when domain_name is set."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for domain_name. Required only when domain_name is set."
  type        = string
  default     = ""
}

# ---------- Monitoring ----------
variable "alert_email" {
  description = "Email address subscribed to the SNS alerts topic. Leave empty to skip the subscription."
  type        = string
  default     = ""
}
