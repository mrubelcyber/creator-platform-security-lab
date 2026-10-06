# ---------------------------------------------------------------
# Lab 12 (SEC-2552) - Posture remediation for real CSPM findings
# CloudTrail.1/2/4 + S3.22/23, IAM.7/15/16, IAM.18, IAM.2, SSM.6/7,
# EC2.172, EC2.182, Account.1. Every fix is proven cleared in Security Hub.
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  partition        = data.aws_partition.current.partition
  trail_name       = "${var.name_prefix}-lab-cspm-trail"
  trail_arn        = "arn:${local.partition}:cloudtrail:${var.aws_region}:${local.account_id}:trail/${local.trail_name}"
  trail_bucket     = "${var.name_prefix}-lab-cspm-trail-${local.account_id}"
  trail_bucket_arn = "arn:${local.partition}:s3:::${local.trail_bucket}"
  trail_key_name   = "${var.name_prefix}-lab-cspm-trail-key"
  support_role     = "${var.name_prefix}-lab-support-role"
  ssm_setting_arn  = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:servicesetting"
  # literal on purpose: import IDs must be known before data sources are read
  change_password_policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}
