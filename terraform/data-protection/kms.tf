# ---------------------------------------------------------------
# Lab 9 (SEC-2549) - Part A: our own key (customer managed KMS key)
# ---------------------------------------------------------------

# Read-only lookup: which AWS account are we in?
data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  admin_role_arn     = "arn:aws:iam::${local.account_id}:role/${var.admin_role_name}"
  flow_log_group_arn = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/${var.name_prefix}-lab/vpc-flow-logs"
}

resource "aws_kms_key" "data" {
  description              = "Lab 9 - encrypts Creator Platform lab data (flow logs, S3, SSM). SEC-2549"
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation      = true
  rotation_period_in_days  = var.key_rotation_days
  deletion_window_in_days  = var.key_deletion_window_days

  # The guest list - the same 5 rules we pasted in the console (9.2 + 9.3a)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowAccessForKeyAdministrators"
        Effect    = "Allow"
        Principal = { AWS = local.admin_role_arn }
        Action = [
          "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
          "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
          "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion", "kms:RotateKeyOnDemand",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowUseOfTheKey"
        Effect    = "Allow"
        Principal = { AWS = local.admin_role_arn }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowAttachmentOfPersistentResources"
        Effect    = "Allow"
        Principal = { AWS = local.admin_role_arn }
        Action    = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
        Resource  = "*"
        Condition = { Bool = { "kms:GrantIsForAWSResource" = "true" } }
      },
      {
        Sid       = "AllowCloudWatchLogsForFlowLogGroupOnly"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.flow_log_group_arn }
        }
      },
    ]
  })

  tags = {
    Name = "${var.name_prefix}-lab-data-key"
  }
}

# The friendly name - alias/cp-lab-data-key
resource "aws_kms_alias" "data" {
  name          = "alias/${var.name_prefix}-lab-data-key"
  target_key_id = aws_kms_key.data.key_id
}
