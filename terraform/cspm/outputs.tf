output "config_bucket" {
  value = aws_s3_bucket.config.bucket
}

output "config_recorder" {
  value = aws_config_configuration_recorder.this.name
}

output "standards_subscriptions" {
  value = [
    aws_securityhub_standards_subscription.fsbp.id,
    aws_securityhub_standards_subscription.cis.id,
  ]
}
