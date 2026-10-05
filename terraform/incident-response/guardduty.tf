# GuardDuty: foundational sources + S3 Protection only (30-day trial, disabled at lab end)
resource "aws_guardduty_detector" "this" {
  #checkov:skip=CKV2_AWS_3:Single account, no AWS Organization - no delegated admin/org config possible. Production: org configuration with auto-enable (SEC-2551)
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
  tags                         = merge(local.tags, { Name = "${var.name_prefix}-lab-guardduty" })
}

locals {
  # Off on purpose: no EKS/RDS/EC2/Lambda workloads. Runtime Monitoring would create a
  # GuardDuty-managed VPC endpoint in cp-lab-vpc and block VPC deletion at cleanup.
  guardduty_features = {
    S3_DATA_EVENTS         = "ENABLED"
    EBS_MALWARE_PROTECTION = "DISABLED"
    RDS_LOGIN_EVENTS       = "DISABLED"
    EKS_AUDIT_LOGS         = "DISABLED"
    LAMBDA_NETWORK_LOGS    = "DISABLED"
    RUNTIME_MONITORING     = "DISABLED"
  }
}

resource "aws_guardduty_detector_feature" "this" {
  for_each    = local.guardduty_features
  detector_id = aws_guardduty_detector.this.id
  name        = each.key
  status      = each.value
}
