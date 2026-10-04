variable "aws_region" {
  description = "AWS region for the Creator Platform network."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every Name tag (cp = Creator Platform)."
  type        = string
  default     = "cp"
}

variable "vpc_cidr" {
  description = "Address range for the whole VPC (the land)."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR, like 10.20.0.0/16."
  }
}

variable "availability_zone" {
  description = "Data center building (AZ) for both subnets."
  type        = string
  default     = "us-east-1a"
}

variable "public_subnet_cidr" {
  description = "Address range for the public room (web tier)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Address range for the private room (database tier)."
  type        = string
  default     = "10.20.11.0/24"
}

variable "db_port" {
  description = "Database port (PostgreSQL)."
  type        = number
  default     = 5432
}

variable "flow_log_retention_days" {
  description = "How many days to keep VPC flow logs."
  type        = number
  default     = 7
}
