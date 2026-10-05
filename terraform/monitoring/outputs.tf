output "trail_arn" {
  description = "CloudTrail trail ARN."
  value       = aws_cloudtrail.main.arn
}

output "logs_bucket" {
  description = "Bucket that receives CloudTrail files and S3 access logs."
  value       = aws_s3_bucket.logs.id
}

output "alerts_topic_arn" {
  description = "Encrypted SNS topic for security alarms."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "The security alarms."
  value       = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]
}
