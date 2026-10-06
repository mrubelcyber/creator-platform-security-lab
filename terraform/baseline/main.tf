# ---------------------------------------------------------------
# Account baseline - free hardening kept after the Lab 12 cleanup (SEC-2552).
# Moved here from terraform/posture and terraform/cspm with `terraform state mv`:
# nothing was destroyed or recreated. Tagged Lab=baseline so lab cleanups KEEP it.
# ---------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  partition       = data.aws_partition.current.partition
  support_role    = "${var.name_prefix}-lab-support-role"
  analyzer_name   = "${var.name_prefix}-lab-access-analyzer"
  ssm_setting_arn = "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:servicesetting"
}
