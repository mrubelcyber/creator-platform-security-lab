data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  bucket_arn = "arn:aws:s3:::${var.uploads_bucket_name}"
}

# 1. Permission boundary: the most the app role can EVER do
data "aws_iam_policy_document" "app_boundary" {
  statement {
    sid       = "S3UploadsBucketOnly"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.bucket_arn, "${local.bucket_arn}/*"]
  }
  statement {
    sid       = "OwnLogStreamsOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/creator-platform/*"]
  }
}

resource "aws_iam_policy" "app_boundary" {
  name        = "cp-app-boundary"
  description = "Permission boundary (ceiling) for the Creator Platform app role"
  policy      = data.aws_iam_policy_document.app_boundary.json
}

# 2. Trust: only ECS tasks running in THIS account may use the role
data "aws_iam_policy_document" "app_trust" {
  statement {
    sid     = "EcsTasksFromThisAccountOnly"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "app" {
  name                 = "creator-platform-app"
  description          = "Runtime role for the Creator Platform app (least privilege)"
  assume_role_policy   = data.aws_iam_policy_document.app_trust.json
  permissions_boundary = aws_iam_policy.app_boundary.arn
  max_session_duration = 3600
}

# 3. What the app actually gets: objects under uploads/ only
data "aws_iam_policy_document" "app_s3" {
  statement {
    sid       = "ListUploadsPrefixOnly"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.uploads_prefix}*"]
    }
  }
  statement {
    sid       = "ReadWriteUploadObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.bucket_arn}/${var.uploads_prefix}*"]
  }
}

resource "aws_iam_role_policy" "app_s3" {
  name   = "creator-platform-app-s3"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_s3.json
}
