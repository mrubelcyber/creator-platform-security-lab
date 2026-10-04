# ---------------------------------------------------------------
# Lab 8 (SEC-2548) - Part E: the CCTV (VPC Flow Logs)
# ---------------------------------------------------------------

# Read-only lookup: which AWS account are we in?
data "aws_caller_identity" "current" {}

# 1) The notebook: where flow log lines are written
resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:Lab keeps flow logs 7 days to control cost. Production keeps 365 days or archives to S3.
  #checkov:skip=CKV_AWS_158:Uses AWS default encryption at rest. Customer managed KMS key is added in Lab 9.
  name              = "/${var.name_prefix}-lab/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = {
    Name = "${var.name_prefix}-flow-log-group"
  }
}

# 2a) Who may wear the role: ONLY the flow logs service, ONLY for
#     our account (confused-deputy protection, same as the console)
data "aws_iam_policy_document" "flow_logs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-vpc-flow-logs-role"
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_trust.json
}

# 2b) What the role may do: write ONLY into our flow log group
#     (tighter than the console's "Resource": "*")
data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    sid    = "WriteToFlowLogGroupOnly"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  statement {
    sid       = "FindLogGroups"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name_prefix}-vpc-flow-logs-write"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

# 3) The camera: record ALL traffic in the VPC, every 60 seconds
resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.name_prefix}-vpc-flow-log"
  }
}
