# The responder. Code: lambda/ir-responder/responder.py (CodeSha256 matched AWS in 11.9)
resource "aws_lambda_function" "responder" {
  #checkov:skip=CKV_AWS_50:Single small function; decisions logged as JSON (KMS log group) and every action is in CloudTrail. Tracing adds IAM and drift (SEC-2551)
  #checkov:skip=CKV_AWS_272:Residual risk - no AWS Signer profile in the lab. Production: signing profile + code-signing config, updates only via pipeline (SEC-2551)
  #checkov:skip=CKV_AWS_115:Reserved concurrency can fail on low-quota accounts. Production: reserve a few to cap floods and guarantee responder capacity (SEC-2551)
  #checkov:skip=CKV_AWS_173:Env vars hold no secrets (ARNs/names); encrypted at rest with aws/lambda - Decrypt events proven in 11.8 (SEC-2551)
  #checkov:skip=CKV_AWS_117:Calls only public AWS APIs (IAM/S3/SNS); a VPC needs NAT or endpoints for no security gain here (SEC-2551)
  function_name    = local.function_name
  description      = "Lab 11 IR responder: contain cp-lab11-* roles, restore data-bucket BPA, notify (SEC-2551)"
  role             = aws_iam_role.responder.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "responder.handler"
  filename         = "${path.module}/${var.lambda_zip_path}"
  source_code_hash = var.lambda_code_sha256 != "" ? var.lambda_code_sha256 : null
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      DRY_RUN         = tostring(var.dry_run)
      TOPIC_ARN       = data.aws_sns_topic.alerts.arn
      DATA_BUCKET     = local.data_bucket_name
      ROLE_PREFIX     = "${var.name_prefix}-lab11-"
      PROTECTED_ROLES = join(",", var.protected_roles)
      SELF_ROLE       = local.role_name
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.responder.name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  tags       = merge(local.tags, { Name = local.function_name })
  depends_on = [aws_iam_role_policy.responder]
}
