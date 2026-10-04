# ---------------------------------------------------------------
# Lab 8 (SEC-2548) - Part D: the room guards (network ACLs)
# NACLs are STATELESS: every conversation needs an IN rule and an
# OUT rule. Rules are checked from the lowest number up; the first
# match wins; anything unmatched hits the final "*" deny.
# ---------------------------------------------------------------

# Default NACL: take it over and leave it with NO rules = deny all.
# Any new subnet that nobody assigns is locked down (secure default).
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  tags = {
    Name = "${var.name_prefix}-default-nacl"
  }
}

# Private room guard (database tier) - same rules as the console
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private.id]

  # IN: questions from the web tier to the database door
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.public_subnet_cidr
    from_port  = var.db_port
    to_port    = var.db_port
  }

  # OUT: answers back to the web servers' temporary doors
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.public_subnet_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.name_prefix}-private-nacl"
    Tier = "private"
  }
}

# Public room guard (web tier) - stricter than the console version
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id]

  # IN 100: customers reach the website (conversation 1 request)
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # IN 110: answers to the web server's own calls (conversations 2+3).
  # Linux temporary doors only - keeps 22, 3389 and 5432 closed.
  ingress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # OUT 100: answers back to customers (conversation 1 reply)
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # OUT 110: web server calls HTTPS services (conversation 2 request)
  egress {
    rule_no    = 110
    action     = "allow"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # OUT 120: web server talks to the database (conversation 3 request)
  egress {
    rule_no    = 120
    action     = "allow"
    protocol   = "tcp"
    cidr_block = var.private_subnet_cidr
    from_port  = var.db_port
    to_port    = var.db_port
  }

  tags = {
    Name = "${var.name_prefix}-public-nacl"
    Tier = "public"
  }
}
