# Rules that invoke the responder (patterns pre-encoded so for_each sees one type)
locals {
  responder_rules = {
    gd-findings = {
      description = "Lab 11: GuardDuty findings sev>=4 -> IR responder (SEC-2551)"
      # Target state: no custom test source (lesson learned - PutEvents could fake findings)
      pattern = jsonencode({
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
        detail        = { severity = [{ numeric = [">=", 4] }] }
      })
    }
    s3-control-tamper = {
      description = "Lab 11: BPA/policy/ACL changes on data bucket -> IR responder (SEC-2551)"
      pattern = jsonencode({
        source        = ["aws.s3"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["s3.amazonaws.com"]
          eventName = [
            "PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock",
            "PutBucketPolicy", "DeleteBucketPolicy", "PutBucketAcl",
          ]
          requestParameters = { bucketName = [local.data_bucket_name] }
          # Loop guard at the bus: drop the responder's own remediation calls
          userIdentity = { arn = [{ "anything-but" = { prefix = "arn:aws:sts::${local.account_id}:assumed-role/${local.role_name}/" } }] }
        }
      })
    }
  }
}

resource "aws_cloudwatch_event_rule" "responder" {
  for_each      = local.responder_rules
  name          = "${var.name_prefix}-lab-${each.key}"
  description   = each.value.description
  event_pattern = each.value.pattern
  state         = "ENABLED"
  tags          = merge(local.tags, { Name = "${var.name_prefix}-lab-${each.key}" })
}

resource "aws_lambda_permission" "events" {
  for_each       = aws_cloudwatch_event_rule.responder
  statement_id   = "allow-${each.value.name}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.responder.function_name
  principal      = "events.amazonaws.com"
  source_arn     = each.value.arn
  source_account = local.account_id
}

resource "aws_cloudwatch_event_target" "responder" {
  for_each  = aws_cloudwatch_event_rule.responder
  rule      = each.value.name
  target_id = "responder"
  arn       = aws_lambda_function.responder.arn

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }
}

# Direct to SNS (no code): object deletions in the data bucket, as a readable message
resource "aws_cloudwatch_event_rule" "object_deleted" {
  name        = "${var.name_prefix}-lab-s3-object-deleted"
  description = "Lab 11: data bucket object deletions -> SNS (SEC-2551)"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Deleted"]
    detail        = { bucket = { name = [local.data_bucket_name] } }
  })
  state = "ENABLED"
  tags  = merge(local.tags, { Name = "${var.name_prefix}-lab-s3-object-deleted" })
}

resource "aws_cloudwatch_event_target" "object_deleted" {
  rule      = aws_cloudwatch_event_rule.object_deleted.name
  target_id = "security-alerts"
  arn       = data.aws_sns_topic.alerts.arn

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 10
  }

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      type   = "$.detail.deletion-type"
      who    = "$.detail.requester"
      ip     = "$.detail.source-ip-address"
      time   = "$.time"
    }
    input_template = "\"[CP-IR] S3 object deleted | bucket=<bucket> key=<key> type=<type> requester=<who> ip=<ip> time=<time>\""
  }
}
