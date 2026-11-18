# ---------------------------------------------------------------
# RDS Multi-AZ (primary + synchronous standby) in the DB subnets
# Credentials are generated and stored in AWS Secrets Manager by RDS
# Diagram part: 05-database-rds-multi-az
# ---------------------------------------------------------------

locals {
  db_port = var.db_engine == "postgres" ? 5432 : 3306

  db_engine_version = var.db_engine == "postgres" ? "16" : "8.0"

  db_log_exports = var.db_engine == "postgres" ? ["postgresql", "upgrade"] : ["error", "slowquery"]
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = aws_subnet.db[*].id

  tags = { Name = "${local.name_prefix}-db-subnets" }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-db"
  engine         = var.db_engine
  engine_version = local.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  port     = local.db_port

  # RDS creates the master password and stores it in Secrets Manager
  manage_master_user_password = true

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period         = 7
  backup_window                   = "02:00-03:00"
  maintenance_window              = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = local.db_log_exports

  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = !var.db_deletion_protection

  tags = { Name = "${local.name_prefix}-db" }
}
