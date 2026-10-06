variable "aws_region" {
  description = "Region for all Lab 12 CSPM resources"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in every resource name"
  type        = string
  default     = "cp"
}

variable "config_retention_days" {
  description = "Days to keep Config snapshots/history in the lab bucket"
  type        = number
  default     = 30
}

variable "retired_kms_key_arns" {
  description = "KMS keys retired on purpose (PendingDeletion) whose KMS.3 finding is accepted. Set in gitignored terraform.tfvars; [] = rule skipped."
  type        = list(string)
  default     = []
}
