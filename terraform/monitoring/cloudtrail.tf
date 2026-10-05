# ---------------------------------------------------------------
# CloudTrail - single-region trail, KMS, validation, CloudWatch Logs
# ---------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  #checkov:skip=CKV_AWS_338:30 days in CloudWatch Logs is for fast detection; the long-term copy is in S3 (90 days, validated).
  name              = "/${var.name_prefix}-lab/cloudtrail"
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_id        = data.aws_kms_alias.data_key.target_key_arn

  tags = {
    Name = "${var.name_prefix}-lab-cloudtrail-logs"
  }
}

# Who may wear the role: only our trail, in our account
data "aws_iam_policy_document" "cloudtrail_assume" {
  statement {
    sid     = "AllowOnlyCpLabTrailToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cwl" {
  name               = "${var.name_prefix}-lab-cloudtrail-cwl-role"
  description        = "Lab 10 - lets CloudTrail trail ${local.trail_name} write to /${var.name_prefix}-lab/cloudtrail. SEC-2550"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume.json

  tags = {
    Name = "${var.name_prefix}-lab-cloudtrail-cwl-role"
  }
}

# What the role may do: write CloudTrail's own streams in ONE log group (no read, no delete)
data "aws_iam_policy_document" "cloudtrail_cwl_write" {
  statement {
    sid       = "WriteToCpLabCloudTrailLogGroupOnly"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:log-stream:${local.account_id}_CloudTrail_${var.aws_region}*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cwl" {
  name   = "${var.name_prefix}-lab-cloudtrail-cwl-write"
  role   = aws_iam_role.cloudtrail_cwl.id
  policy = data.aws_iam_policy_document.cloudtrail_cwl_write.json
}

resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_67:Free account plan does not support multi-Region trails. IAM/STS/sign-in still log to us-east-1.
  #checkov:skip=CKV_AWS_252:Alerting is done by CloudWatch metric filters + alarms -> SNS, not per-file delivery notices.
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = false
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true
  kms_key_id                    = data.aws_kms_alias.data_key.target_key_arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cwl.arn

  # Selector 1: all management events, read + write, KMS NOT excluded
  advanced_event_selector {
    name = "Management events - read and write, KMS included"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # Selector 2: object-level events for the data bucket only (not the logs bucket - no loop, no noise)
  advanced_event_selector {
    name = "S3 data events - cp-lab-data bucket only"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:s3:::${local.data_bucket_name}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.logs, aws_iam_role_policy.cloudtrail_cwl]

  tags = {
    Name = local.trail_name
  }
}
