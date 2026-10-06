# Account-level settings (not taggable). Destroying these resources restores the AWS defaults.

# SSM.7 - block public sharing of SSM documents
resource "aws_ssm_service_setting" "block_public_document_sharing" {
  setting_id    = "${local.ssm_setting_arn}/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}

# SSM.6 - SSM Automation script output goes to CloudWatch Logs
resource "aws_ssm_service_setting" "automation_logging" {
  setting_id    = "${local.ssm_setting_arn}/ssm/automation/customer-script-log-destination"
  setting_value = "CloudWatch"
}

# EC2.182 - no public sharing of EBS snapshots in this Region
resource "aws_ebs_snapshot_block_public_access" "this" {
  state = "block-all-sharing"
}

# EC2.172 - VPC Block Public Access: block inbound internet traffic, allow outbound
resource "aws_vpc_block_public_access_options" "this" {
  internet_gateway_block_mode = "block-ingress"
}

# Account.1 / CIS 1.2 - security alternate contact (values from gitignored terraform.tfvars)
resource "aws_account_alternate_contact" "security" {
  alternate_contact_type = "SECURITY"
  name                   = var.security_contact.name
  title                  = var.security_contact.title
  email_address          = var.security_contact.email
  phone_number           = var.security_contact.phone
}
