# ---------------------------------------------------------------
# Alerts - encrypted SNS topic + metric filters + alarms
# ---------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name              = "${var.name_prefix}-lab-security-alerts" # Standard (alarms cannot publish to FIFO)
  display_name      = "CP Lab Alerts"
  kms_master_key_id = data.aws_kms_alias.data_key.target_key_arn # NOT aws/sns - alarms cannot use it

  tags = {
    Name = "${var.name_prefix}-lab-security-alerts"
  }
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid    = "AllowAccountOwnerToManageTopic"
    effect = "Allow"
    actions = [
      "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:AddPermission",
      "sns:RemovePermission", "sns:DeleteTopic", "sns:Subscribe",
      "sns:ListSubscriptionsByTopic", "sns:Publish",
    ]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  # Only OUR alarms (name starts with cp-lab-) may publish
  statement {
    sid       = "AllowOnlyCpLabAlarmsToPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${var.aws_region}:${local.account_id}:alarm:${var.name_prefix}-lab-*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "DenyPublishWithoutTls"
    effect    = "Deny"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

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

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

# Only created when an email is given at apply time; must be confirmed from the inbox
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# The 4 alerts as one table. errorCode = "AccessDenied" only, so DryRunOperation is not an alert.
locals {
  alarms = {
    "kms-decrypt-denied" = {
      log_group   = aws_cloudwatch_log_group.cloudtrail.name
      pattern     = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"Decrypt\") && ($.errorCode = \"AccessDenied\") }"
      metric      = "KmsDecryptAccessDenied"
      threshold   = 1
      description = "Lab 10 - KMS Decrypt AccessDenied on any key (CloudTrail). Possible data access probe. SEC-2550"
    }
    "kms-key-disable-or-delete" = {
      log_group   = aws_cloudwatch_log_group.cloudtrail.name
      pattern     = "{ ($.eventSource = \"kms.amazonaws.com\") && (($.eventName = \"DisableKey\") || ($.eventName = \"ScheduleKeyDeletion\")) }"
      metric      = "KmsKeyDisableOrDeletion"
      threshold   = 1
      description = "Lab 10 - KMS key disable or scheduled deletion attempt (CIS). SEC-2550"
    }
    "kms-key-policy-change" = {
      log_group   = aws_cloudwatch_log_group.cloudtrail.name
      pattern     = "{ ($.eventSource = \"kms.amazonaws.com\") && ($.eventName = \"PutKeyPolicy\") }"
      metric      = "KmsKeyPolicyChange"
      threshold   = 1
      description = "Lab 10 - KMS key policy changed (PutKeyPolicy), success or attempt. SEC-2550"
    }
    "vpc-flow-rejects" = {
      log_group   = "/${var.name_prefix}-lab/vpc-flow-logs" # from terraform/network (Lab 8)
      pattern     = "[version, account, eni, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", logstatus]"
      metric      = "VpcFlowLogRejects"
      threshold   = var.flow_reject_threshold
      description = "Lab 10 - ${var.flow_reject_threshold}+ rejected connections in 5 min in cp-lab-vpc (scan or burst). Tune threshold when workloads run. SEC-2550"
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each       = local.alarms
  name           = "${var.name_prefix}-lab-${each.key}-filter"
  log_group_name = each.value.log_group
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.value.metric
    namespace     = "CPLab/Security"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${var.name_prefix}-lab-${each.key}"
  alarm_description   = each.value.description
  namespace           = "CPLab/Security"
  metric_name         = aws_cloudwatch_log_metric_filter.this[each.key].metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanOrEqualToThreshold" # >= (step 7a lesson: > 1 misses a single event)
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.name_prefix}-lab-${each.key}"
  }
}
