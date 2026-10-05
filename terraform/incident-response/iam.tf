# Responder identity: least privilege, proven with the IAM policy simulator in 11.3
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "responder" {
  name               = local.role_name
  description        = "Lab 11 IR responder - least privilege, cp-lab11-* roles only (SEC-2551)"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = merge(local.tags, { Name = local.role_name })
}

data "aws_iam_policy_document" "responder" {
  statement {
    sid       = "WriteOwnLogsOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.responder.arn}:*"]
  }

  statement {
    sid       = "PublishSecurityAlerts"
    actions   = ["sns:Publish"]
    resources = [data.aws_sns_topic.alerts.arn]
  }

  # The key may be used only through SNS (encrypting alerts), never directly
  statement {
    sid       = "UseDataKeyOnlyViaSns"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = [data.aws_kms_alias.data_key.target_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${var.aws_region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "SendFailedEventsToDlq"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  statement {
    sid       = "QuarantineLabTestRolesOnly"
    actions   = ["iam:GetRole", "iam:ListRolePolicies", "iam:PutRolePolicy", "iam:TagRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.name_prefix}-lab11-*"]
  }

  statement {
    sid       = "RestoreDataBucketPublicAccessBlock"
    actions   = ["s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock"]
    resources = ["arn:aws:s3:::${local.data_bucket_name}"]
  }

  # Survives future mistakes: even "iam:* on *" added later cannot touch these
  statement {
    sid     = "NeverTouchAdminOrSelf"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-admin-role",
      "arn:aws:iam::${local.account_id}:role/${local.role_name}",
    ]
  }
}

resource "aws_iam_role_policy" "responder" {
  name   = "${var.name_prefix}-lab-ir-lambda-policy"
  role   = aws_iam_role.responder.id
  policy = data.aws_iam_policy_document.responder.json
}
