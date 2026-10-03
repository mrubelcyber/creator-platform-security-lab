output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "app_boundary_arn" {
  value = aws_iam_policy.app_boundary.arn
}
