output "vpc_id" {
  description = "ID of the Creator Platform VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public (web) subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private (database) subnet."
  value       = aws_subnet.private.id
}

output "web_security_group_id" {
  description = "ID of the web tier security group."
  value       = aws_security_group.web.id
}

output "db_security_group_id" {
  description = "ID of the database tier security group."
  value       = aws_security_group.db.id
}

output "flow_log_group_name" {
  description = "CloudWatch log group that receives VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
