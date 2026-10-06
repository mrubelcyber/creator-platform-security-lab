variable "aws_region" {
  description = "Region for all Lab 12 posture fixes"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in every resource name"
  type        = string
  default     = "cp"
}

variable "log_retention_days" {
  description = "Days to keep CloudTrail log files in the lab trail bucket"
  type        = number
  default     = 30
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

variable "legacy_change_password_users" {
  description = "IAM users with IAMUserChangePassword attached directly (IAM.2 / CIS 1.14). Phase 1: list them so Terraform adopts (imports) the attachment. Phase 2: set [] so Terraform detaches it."
  type        = set(string)
  default     = []
}
