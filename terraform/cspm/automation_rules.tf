# ---------------------------------------------------------------
# Lab 12 (SEC-2552) - accepted risks recorded as code.
# Matching Security Hub findings are SUPPRESSED with a note (reason, ticket, review point).
# Rules act when a finding is created or updated, so existing findings change at their next evaluation.
# ---------------------------------------------------------------

data "aws_vpcs" "default" {
  filter {
    name   = "is-default"
    values = ["true"]
  }
}

locals {
  note_by          = "terraform/cspm (SEC-2552)"
  default_vpc_arns = [for id in data.aws_vpcs.default.ids : "arn:${local.partition}:ec2:${var.aws_region}:${local.account_id}:vpc/${id}"]

  accepted_risks = {
    sandbox-services-off = {
      order    = 1
      controls = ["GuardDuty.1", "Inspector.1", "Inspector.2", "Inspector.3", "Inspector.4", "Macie.1", "CloudTrail.5"]
      scoped   = false
      prefixes = []
      note     = "Accepted risk (SEC-2552): sandbox account with no workloads or sensitive data. GuardDuty proven in Lab 11, CloudTrail to CloudWatch Logs in Lab 10. Production: enabled org-wide. Review at Lab 12 cleanup."
    }
    root-virtual-mfa = {
      order    = 2
      controls = ["IAM.6"]
      scoped   = false
      prefixes = []
      note     = "Accepted risk (SEC-2552): root has virtual MFA and is used only for root-only billing/account tasks (verified in CloudTrail). Production: FIDO2 hardware key or centralized root access. Review at Lab 12 cleanup."
    }
    lab-log-buckets = {
      order    = 3
      controls = ["S3.9", "CloudTrail.7"]
      scoped   = true
      prefixes = ["arn:${local.partition}:s3:::${var.name_prefix}-lab-", "arn:${local.partition}:cloudtrail:${var.aws_region}:${local.account_id}:trail/${var.name_prefix}-lab-"]
      note     = "Accepted risk (SEC-2552): lab-only log buckets, same decision as the Checkov CKV_AWS_18 skips. Production: log-archive account with server access logging. Review at Lab 12 cleanup."
    }
    retired-kms-keys = {
      order    = 4
      controls = ["KMS.3"]
      scoped   = true
      prefixes = var.retired_kms_key_arns
      note     = "Intended (SEC-2551/SEC-2552): key retired in the Lab 11 cleanup and scheduled for deletion on purpose. Finding ends when the key is deleted."
    }
    unused-default-vpc = {
      order    = 5
      controls = ["EC2.6", "EC2.10", "EC2.55", "EC2.56", "EC2.57", "EC2.58", "EC2.60"]
      scoped   = true
      prefixes = local.default_vpc_arns
      note     = "Accepted risk (SEC-2552): default VPC kept but unused (0 ENIs), default SG has no rules, VPC Block Public Access blocks inbound internet. Endpoints would cost ~$45+/month. Re-open if anything is deployed here."
    }
  }

  # a resource-scoped rule with no resources would suppress nothing useful - skip it
  active_rules = { for k, r in local.accepted_risks : k => r if !(r.scoped && length(r.prefixes) == 0) }
}

resource "aws_securityhub_automation_rule" "accepted" {
  for_each    = local.active_rules
  rule_name   = "${var.name_prefix}-lab12-accepted-${each.key}"
  rule_order  = each.value.order
  rule_status = "ENABLED"
  description = each.value.note

  actions {
    type = "FINDING_FIELDS_UPDATE"
    finding_fields_update {
      workflow {
        status = "SUPPRESSED"
      }
      note {
        text       = each.value.note
        updated_by = local.note_by
      }
    }
  }

  criteria {
    product_name {
      comparison = "EQUALS"
      value      = "Security Hub"
    }

    dynamic "compliance_security_control_id" {
      for_each = each.value.controls
      content {
        comparison = "EQUALS"
        value      = compliance_security_control_id.value
      }
    }

    dynamic "resource_id" {
      for_each = each.value.prefixes
      content {
        comparison = "PREFIX"
        value      = resource_id.value
      }
    }
  }

  depends_on = [aws_securityhub_account.this]
}
