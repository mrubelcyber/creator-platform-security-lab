resource "aws_s3_bucket" "creator_uploads" {
  bucket = "creator-platform-training-uploads"

  tags = {
    Name        = "Creator Platform Uploads"
    Environment = "training"
  }
}

resource "aws_s3_bucket_public_access_block" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "access_logs" {
  bucket = "creator-platform-training-access-logs"

  tags = {
    Name        = "Creator Platform Access Logs"
    Environment = "training"
  }
}

resource "aws_s3_bucket_logging" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "creator-uploads/"
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "manage-access-logs"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_sns_topic" "s3_events" {
  name              = "creator-platform-s3-events"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_s3_bucket_notification" "creator_uploads" {
  bucket = aws_s3_bucket.creator_uploads.id

  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket_notification" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = "creator-platform-training-uploads-replica"

  tags = {
    Name        = "Creator Platform Uploads Replica"
    Environment = "training"
    Purpose     = "disaster-recovery"
  }
}

resource "aws_s3_bucket" "access_logs_replica" {
  provider = aws.dr
  bucket   = "creator-platform-training-access-logs-replica"

  tags = {
    Name        = "Creator Platform Access Logs Replica"
    Environment = "training"
    Purpose     = "disaster-recovery"
  }
}

resource "aws_s3_bucket_versioning" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  rule {
    id     = "manage-creator-replica"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  rule {
    id     = "manage-access-logs-replica"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_logging" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  target_bucket = aws_s3_bucket.access_logs_replica.id
  target_prefix = "creator-uploads-replica/"
}

resource "aws_s3_bucket_logging" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  target_bucket = aws_s3_bucket.access_logs_replica.id
  target_prefix = "access-logs-replica/"
}

resource "aws_sns_topic" "s3_events_dr" {
  provider          = aws.dr
  name              = "creator-platform-s3-events-dr"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_s3_bucket_notification" "creator_uploads_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.creator_uploads_replica.id

  topic {
    topic_arn = aws_sns_topic.s3_events_dr.arn
    events    = ["s3:ObjectCreated:*"]
  }
}

resource "aws_s3_bucket_notification" "access_logs_replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.access_logs_replica.id

  topic {
    topic_arn = aws_sns_topic.s3_events_dr.arn
    events    = ["s3:ObjectCreated:*"]
  }
}
