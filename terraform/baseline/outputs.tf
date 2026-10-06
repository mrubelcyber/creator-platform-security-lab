output "support_role_arn" {
  value = aws_iam_role.support.arn
}

output "access_analyzer_arn" {
  value = aws_accessanalyzer_analyzer.external.arn
}
