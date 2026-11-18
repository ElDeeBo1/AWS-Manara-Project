# ---------------------------------------------------------------
# VPC, subnets, Internet Gateway, NAT Gateways, route tables, NACLs
# Diagram part: 02-vpc-network-layout
# ---------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

# ----- Subnets -----
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${count.index == 0 ? "a" : "b"}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.app_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.name_prefix}-app-${count.index == 0 ? "a" : "b"}", Tier = "app" }
}

resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.db_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.name_prefix}-db-${count.index == 0 ? "a" : "b"}", Tier = "db" }
}

# ----- NAT Gateways (one per AZ, in the public subnets) -----
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = { Name = "${local.name_prefix}-nat-eip-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${local.name_prefix}-nat-${count.index == 0 ? "a" : "b"}" }

  depends_on = [aws_internet_gateway.main]
}

# ----- Route tables -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Each app subnet routes outbound traffic through the NAT Gateway in its own AZ
resource "aws_route_table" "app" {
  count  = 2
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = { Name = "${local.name_prefix}-rt-app-${count.index == 0 ? "a" : "b"}" }
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# DB subnets have no route to the internet at all
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-rt-db" }
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# ----- Network ACLs (stateless, second layer of defence next to Security Groups) -----
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.public[*].id

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Return traffic for connections started from inside the VPC (NAT, ALB to targets)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${local.name_prefix}-nacl-public" }
}

resource "aws_network_acl" "app" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.app[*].id

  # HTTP from the ALB (which lives in the public subnets)
  dynamic "ingress" {
    for_each = { for i, c in local.public_subnet_cidrs : tostring(i) => c }
    content {
      rule_no    = 100 + tonumber(ingress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 80
      to_port    = 80
    }
  }

  # Return traffic from the internet (through NAT) and from the database
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${local.name_prefix}-nacl-app" }
}

resource "aws_network_acl" "db" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = aws_subnet.db[*].id

  # Database port, only from the app subnets
  dynamic "ingress" {
    for_each = { for i, c in local.app_subnet_cidrs : tostring(i) => c }
    content {
      rule_no    = 100 + tonumber(ingress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = local.db_port
      to_port    = local.db_port
    }
  }

  # Synchronous replication between the primary and the standby
  dynamic "ingress" {
    for_each = { for i, c in local.db_subnet_cidrs : tostring(i) => c }
    content {
      rule_no    = 200 + tonumber(ingress.key)
      protocol   = "-1"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 0
      to_port    = 0
    }
  }

  # Replies to the app subnets
  dynamic "egress" {
    for_each = { for i, c in local.app_subnet_cidrs : tostring(i) => c }
    content {
      rule_no    = 100 + tonumber(egress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  dynamic "egress" {
    for_each = { for i, c in local.db_subnet_cidrs : tostring(i) => c }
    content {
      rule_no    = 200 + tonumber(egress.key)
      protocol   = "-1"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 0
      to_port    = 0
    }
  }

  tags = { Name = "${local.name_prefix}-nacl-db" }
}
