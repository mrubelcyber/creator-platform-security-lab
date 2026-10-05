# Security Hub CSPM: 30-day free trial on first enable (per account, per Region).
# Default standards OFF so we choose exactly two; consolidated control findings ON.
resource "aws_securityhub_account" "this" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
  depends_on                = [aws_config_configuration_recorder_status.this]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${local.partition}:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]

  # First-time enablement can take longer than the 3m provider default
  timeouts {
    create = "15m"
    delete = "15m"
  }
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:${local.partition}:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/5.0.0"
  depends_on    = [aws_securityhub_account.this]

  # First-time enablement can take longer than the 3m provider default
  timeouts {
    create = "15m"
    delete = "15m"
  }
}
