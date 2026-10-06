# Customer managed key for CloudTrail log files (CloudTrail.2 / CIS 3.5) with rotation (KMS.4 / CIS 3.6)
data "aws_iam_policy_document" "trail_key" {
  #checkov:skip=CKV_AWS_109:Key policy - Resource "*" means this key only; the root statement delegates to IAM (AWS default key policy) (SEC-2552)
  #checkov:skip=CKV_AWS_111:Key policy - Resource "*" means this key only; the root statement delegates to IAM (AWS default key policy) (SEC-2552)
  #checkov:skip=CKV_AWS_356:Key policy - Resource "*" means this key only (SEC-2552)
  statement {
    sid       = "EnableIAMPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "AllowCloudTrailToEncryptLogs"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "AllowCloudTrailToDescribeKey"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "trail" {
  description             = "Lab 12 - encrypts CloudTrail log files for ${local.trail_name}. SEC-2552"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.trail_key.json
  tags                    = { Name = local.trail_key_name }
}

resource "aws_kms_alias" "trail" {
  name          = "alias/${local.trail_key_name}"
  target_key_id = aws_kms_key.trail.key_id
}
