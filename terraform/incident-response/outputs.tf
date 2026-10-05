output "guardduty_detector_id" {
  value = aws_guardduty_detector.this.id
}

output "responder_function_arn" {
  value = aws_lambda_function.responder.arn
}

output "rule_arns" {
  value = merge(
    { for k, r in aws_cloudwatch_event_rule.responder : k => r.arn },
    { s3-object-deleted = aws_cloudwatch_event_rule.object_deleted.arn },
  )
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
