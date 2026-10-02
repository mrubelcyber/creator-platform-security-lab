data "aws_iam_policy_document" "s3_replication_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "s3_replication" {
  name               = "creator-platform-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.s3_replication_assume_role.json

  tags = {
    Name        = "Creator Platform S3 Replication"
    Environment = "training"
  }
}

data "aws_iam_policy_document" "s3_replication" {
  statement {
    sid    = "ReadSourceBucketConfiguration"
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.creator_uploads.arn,
      aws_s3_bucket.access_logs.arn
    ]
  }

  statement {
    sid    = "ReadSourceObjects"
    effect = "Allow"

    actions = [
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionTagging"
    ]

    resources = [
      "${aws_s3_bucket.creator_uploads.arn}/*",
      "${aws_s3_bucket.access_logs.arn}/*"
    ]
  }

  statement {
    sid    = "ReplicateToDestination"
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]

    resources = [
      "${aws_s3_bucket.creator_uploads_replica.arn}/*",
      "${aws_s3_bucket.access_logs_replica.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "s3_replication" {
  name   = "creator-platform-s3-replication-policy"
  role   = aws_iam_role.s3_replication.id
  policy = data.aws_iam_policy_document.s3_replication.json
}

resource "aws_s3_bucket_replication_configuration" "creator_uploads" {
  depends_on = [
    aws_s3_bucket_versioning.creator_uploads,
    aws_s3_bucket_versioning.creator_uploads_replica
  ]

  role   = aws_iam_role.s3_replication.arn
  bucket = aws_s3_bucket.creator_uploads.id

  rule {
    id     = "replicate-creator-uploads"
    status = "Enabled"

    destination {
      bucket = aws_s3_bucket.creator_uploads_replica.arn
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "access_logs" {
  depends_on = [
    aws_s3_bucket_versioning.access_logs,
    aws_s3_bucket_versioning.access_logs_replica
  ]

  role   = aws_iam_role.s3_replication.arn
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "replicate-access-logs"
    status = "Enabled"

    destination {
      bucket = aws_s3_bucket.access_logs_replica.arn
    }
  }
}
