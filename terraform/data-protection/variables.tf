variable "aws_region" {
  description = "AWS region for the Creator Platform data protection controls."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every name (cp = Creator Platform)."
  type        = string
  default     = "cp"
}

variable "admin_role_name" {
  description = "IAM role that administers and uses the data key (from Lab 7)."
  type        = string
  default     = "cp-admin-role"
}

variable "key_rotation_days" {
  description = "How often KMS makes new key material (days)."
  type        = number
  default     = 365

  validation {
    condition     = var.key_rotation_days >= 90 && var.key_rotation_days <= 2560
    error_message = "KMS allows a rotation period between 90 and 2560 days."
  }
}

variable "key_deletion_window_days" {
  description = "Waiting period before a scheduled key deletion happens (days)."
  type        = number
  default     = 7

  validation {
    condition     = var.key_deletion_window_days >= 7 && var.key_deletion_window_days <= 30
    error_message = "KMS allows a deletion waiting period between 7 and 30 days."
  }
}

variable "noncurrent_version_days" {
  description = "Days to keep old (overwritten or deleted) object versions."
  type        = number
  default     = 30
}

variable "db_password" {
  description = "Database password. Passed at apply time only, never saved in code or state."
  type        = string
  sensitive   = true
  ephemeral   = true
  default     = null
}
