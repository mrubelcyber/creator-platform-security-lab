# ---------------------------------------------------------------
# Lab 9 (SEC-2549) - Part D: database password as a SecureString
# ---------------------------------------------------------------

# value_wo = "write-only": Terraform sends the password to AWS but
# NEVER writes it to the state file. The password itself is never in Git.
resource "aws_ssm_parameter" "db_password" {
  name             = "/${var.name_prefix}-lab/db/password"
  description      = "Lab 9 - FAKE db password for testing, SEC-2549"
  type             = "SecureString"
  tier             = "Standard"
  key_id           = aws_kms_key.data.arn
  value_wo         = var.db_password
  value_wo_version = 1

  tags = {
    Name = "${var.name_prefix}-lab-db-password"
  }
}
