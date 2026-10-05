variable "aws_region" {
  description = "AWS region for the Creator Platform monitoring controls (single-region trail: Free plan)."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every name (cp = Creator Platform)."
  type        = string
  default     = "cp"
}

variable "alert_email" {
  description = "Email that receives security alarms. Set at apply time (TF_VAR_alert_email), never committed."
  type        = string
  default     = null
}

variable "cloudtrail_log_retention_days" {
  description = "Days CloudTrail events stay in CloudWatch Logs (fast detection). S3 keeps the long-term copy."
  type        = number
  default     = 30
}

variable "logs_expiration_days" {
  description = "Days log files stay in the logs bucket before they expire."
  type        = number
  default     = 90
}

variable "logs_noncurrent_days" {
  description = "Days old (overwritten or deleted) log file versions are kept."
  type        = number
  default     = 30
}

variable "flow_reject_threshold" {
  description = "Rejected connections per 5 minutes that raise the flow log alarm. Tune when workloads run."
  type        = number
  default     = 10
}
