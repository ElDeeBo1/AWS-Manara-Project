data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Two Availability Zones, as in the architecture diagram
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Subnet plan inside 10.0.0.0/16
  #   public: 10.0.0.0/24,  10.0.1.0/24   (ALB + NAT Gateway)
  #   app:    10.0.10.0/24, 10.0.11.0/24  (EC2 Auto Scaling group)
  #   db:     10.0.20.0/24, 10.0.21.0/24  (RDS Multi-AZ)
  public_subnet_cidrs = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  app_subnet_cidrs    = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  db_subnet_cidrs     = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}
