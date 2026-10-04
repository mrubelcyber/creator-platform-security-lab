# ---------------------------------------------------------------
# Lab 8 (SEC-2548) - Part B: the land, rooms, gate and signs
# ---------------------------------------------------------------

# The land: our private network
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = false

  tags = {
    Name = "${var.name_prefix}-lab-vpc"
  }
}

# Room 1: public subnet (web tier)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false # Risk 1 fix: no automatic public IPs

  tags = {
    Name = "${var.name_prefix}-public-1a"
    Tier = "public"
  }
}

# Room 2: private subnet (database tier)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-1a"
    Tier = "private"
  }
}

# The front gate to the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Private sign: take over the VPC's MAIN route table and keep it
# local-only. Risk 4 fix: any new subnet is private by default.
resource "aws_default_route_table" "private" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  tags = {
    Name = "${var.name_prefix}-private-rt"
    Tier = "private"
  }
}

# Public sign: its own route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-public-rt"
    Tier = "public"
  }
}

# The one line that makes a room public: 0.0.0.0/0 -> front gate
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Connect each room to its sign explicitly (do not rely on defaults)
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_default_route_table.private.id
}
