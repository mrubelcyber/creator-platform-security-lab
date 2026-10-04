# ---------------------------------------------------------------
# Lab 8 (SEC-2548) - Part C: the door guards (security groups)
# ---------------------------------------------------------------

# Web guard: protects the web/API servers
resource "aws_security_group" "web" {
  #checkov:skip=CKV2_AWS_5:Network only in Lab 8. Web servers attach this group in a later lab.
  name        = "${var.name_prefix}-web-sg"
  description = "Web tier - HTTPS from internet only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-web-sg"
    Tier = "web"
  }
}

# Database guard: protects the database
resource "aws_security_group" "db" {
  #checkov:skip=CKV2_AWS_5:Network only in Lab 8. The database attaches this group in a later lab.
  name        = "${var.name_prefix}-db-sg"
  description = "Database tier - PostgreSQL from web tier only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-db-sg"
    Tier = "database"
  }
}

# ---------- Web guard rules ----------

# IN: customers reach the website on HTTPS only (no 22, no 80)
resource "aws_vpc_security_group_ingress_rule" "web_https_in" {
  security_group_id = aws_security_group.web.id
  description       = "Public HTTPS for Creator Platform API"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# OUT: web servers may talk to the database, nothing else inside
resource "aws_vpc_security_group_egress_rule" "web_to_db" {
  security_group_id            = aws_security_group.web.id
  description                  = "To database tier only"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.db.id
}

# OUT: HTTPS for updates and AWS APIs
resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "Outbound HTTPS for updates and AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Database guard rules ----------

# IN: only servers wearing the web badge, only on the DB port
resource "aws_vpc_security_group_ingress_rule" "db_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from web tier only"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.web.id
}

# OUT: none on purpose. Terraform removes AWS's default
# "allow all outbound" rule, so the database cannot start
# connections out (blocks data exfiltration).

# ---------- Default security group ----------

# Take over the VPC's default group and leave it EMPTY.
# No ingress/egress blocks = Terraform deletes all its rules.
# Risk 5 fix (CIS / Security Hub EC2.2).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-default-sg"
  }
}
