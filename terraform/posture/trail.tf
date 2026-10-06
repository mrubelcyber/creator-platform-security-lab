# CloudTrail.1 / CIS 3.1 (multi-Region, read+write management events), CloudTrail.4 / CIS 3.2 (validation),
# CloudTrail.2 / CIS 3.5 (KMS), S3.22 + S3.23 / CIS 3.8 + 3.9 (all S3 object-level write + read events)
resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV2_AWS_10:CloudWatch Logs delivery (CloudTrail.5) not deployed in Lab 12 - Lab 10 proved it. Production: CWL + metric filters (SEC-2552)
  #checkov:skip=CKV_AWS_252:No SNS notification per log file needed (SEC-2552)
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.trail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${local.partition}:s3"] # all current and future buckets
    }
  }

  tags       = { Name = local.trail_name }
  depends_on = [aws_s3_bucket_policy.trail]
}
