output "trail_arn" {
  value = aws_cloudtrail.this.arn
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.bucket
}

output "trail_key_arn" {
  value = aws_kms_key.trail.arn
}

output "support_role_arn" {
  value = aws_iam_role.support.arn
}
