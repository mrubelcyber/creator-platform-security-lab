output "data_key_arn" {
  description = "ARN of the customer managed KMS key."
  value       = aws_kms_key.data.arn
}

output "data_key_alias" {
  description = "Friendly name of the KMS key."
  value       = aws_kms_alias.data.name
}

output "data_bucket_name" {
  description = "Encrypted S3 bucket for Creator Platform lab data."
  value       = aws_s3_bucket.data.bucket
}

output "db_password_parameter_name" {
  description = "Name of the SecureString parameter (the value is never output)."
  value       = aws_ssm_parameter.db_password.name
}
