# ---------------------------------------------------------------
# Lab 11 (SEC-2551) - Incident Response & Automation
# GuardDuty + CloudTrail/S3 events -> EventBridge -> Lambda responder / SNS
# Validated and scanned in CI; resources were built in CloudShell (not applied).
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}

# Lab 9 key and Lab 10 topic, found by name (owned by other folders)
data "aws_kms_alias" "data_key" {
  name = "alias/${var.name_prefix}-lab-data-key"
}

data "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-lab-security-alerts"
}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  data_bucket_name = "${var.name_prefix}-lab-data-${local.account_id}"
  function_name    = "${var.name_prefix}-lab-ir-responder"
  role_name        = "${var.name_prefix}-lab-ir-lambda-role"
  log_group_name   = "/${var.name_prefix}-lab/ir-responder"
  dlq_name         = "${var.name_prefix}-lab-ir-dlq"
  rule_arn_pattern = "arn:aws:events:${var.aws_region}:${local.account_id}:rule/${var.name_prefix}-lab-*"

  tags = {
    Project = "creator-platform"
    Lab     = "lab-11"
    Ticket  = "SEC-2551"
  }
}
