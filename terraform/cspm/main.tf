# ---------------------------------------------------------------
# Lab 12 (SEC-2552) - Cloud Security Posture Management (CSPM)
# AWS Config (recorder + delivery) -> Security Hub CSPM (FSBP + CIS v5.0.0)
# + IAM Access Analyzer (external access, free). Applied in Lab 12.
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  partition     = data.aws_partition.current.partition
  bucket_name   = "${var.name_prefix}-lab-config-${local.account_id}"
  bucket_arn    = "arn:${local.partition}:s3:::${local.bucket_name}"
  recorder_name = "${var.name_prefix}-lab-config-recorder"
  channel_name  = "${var.name_prefix}-lab-config-channel"
  analyzer_name = "${var.name_prefix}-lab-access-analyzer"
}
