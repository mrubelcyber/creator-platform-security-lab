# ---------------------------------------------------------------
# Lab 10 (SEC-2550) - AWS Security Monitoring
# ---------------------------------------------------------------

# Read-only lookups
data "aws_caller_identity" "current" {}

# The Lab 9 key (terraform/data-protection), found by its friendly name
data "aws_kms_alias" "data_key" {
  name = "alias/${var.name_prefix}-lab-data-key"
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  logs_bucket_name = "${var.name_prefix}-lab-logs-${local.account_id}"
  data_bucket_name = "${var.name_prefix}-lab-data-${local.account_id}"
  trail_name       = "${var.name_prefix}-lab-trail"
  trail_arn        = "arn:aws:cloudtrail:${var.aws_region}:${local.account_id}:trail/${local.trail_name}"
}
