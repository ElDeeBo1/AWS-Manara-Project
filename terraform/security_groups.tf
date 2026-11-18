# ---------------------------------------------------------------
# Security Groups (stateful, tier to tier references)
# Diagram parts: 03-security-waf-alb, 04-compute-asg, 05-database
# ---------------------------------------------------------------

# AWS-managed list of CloudFront origin-facing IP ranges
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# ----- ALB: only CloudFront can reach it -----
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: HTTP from CloudFront only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from CloudFront origin-facing IPs"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                 = "Forward to the app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                 = "tcp"
  from_port                   = 80
  to_port                     = 80
}

# ----- App tier: only the ALB can reach it -----
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "EC2 web tier: HTTP from the ALB only, no SSH"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound via NAT (package installs, SSM) and to the database"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ----- Database: only the app tier can reach it -----
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "RDS: database port from the app tier only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-db-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "Database port from the app tier"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}
