variable "aws_region" {
  description = "Region for the account baseline"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in every resource name"
  type        = string
  default     = "cp"
}

variable "security_contact" {
  description = "Security alternate contact (Account.1 / CIS 1.2). Set in terraform.tfvars, which is gitignored - never commit real values."
  type = object({
    name  = string
    title = string
    email = string
    phone = string
  })
}
