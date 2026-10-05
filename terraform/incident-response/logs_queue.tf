# Responder log group (KMS - key policy lists this ARN) and the dead-letter queue
resource "aws_cloudwatch_log_group" "responder" {
  #checkov:skip=CKV_AWS_338:30 days for operations (as Lab 10); every responder action is also in CloudTrail, kept in S3 with log validation (SEC-2551)
  name              = local.log_group_name
  retention_in_days = 30
  kms_key_id        = data.aws_kms_alias.data_key.target_key_arn
  log_group_class   = "STANDARD"
  tags              = merge(local.tags, { Name = "${var.name_prefix}-lab-ir-responder-logs" })
}

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_name
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600 # 14 days (maximum)
  tags                      = merge(local.tags, { Name = local.dlq_name })
}

data "aws_iam_policy_document" "dlq" {
  # Lambda writes via its IAM role; EventBridge (a service principal) needs this resource policy
  statement {
    sid       = "AllowCpLabRulesToDeadLetter"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.rule_arn_pattern]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.dlq.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}
