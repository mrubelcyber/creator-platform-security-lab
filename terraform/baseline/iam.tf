# IAM.7 / IAM.15 (CIS 1.7) / IAM.16 (CIS 1.8) - strong password policy, no forced expiry
resource "aws_iam_account_password_policy" "this" {
  #checkov:skip=CKV_AWS_9:No forced expiry - CIS v5 removed it and NIST SP 800-63B advises against periodic rotation; long passwords + MFA instead (SEC-2552)
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true # replaces the user-attached IAMUserChangePassword policy (IAM.2)
  password_reuse_prevention      = 24
}

# IAM.18 / CIS 1.16 - a role for AWS Support cases, assumable only from this account with MFA
data "aws_iam_policy_document" "support_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "support" {
  name                 = local.support_role
  description          = "Lab 12 - AWS Support cases only (IAM.18 / CIS 1.16). MFA required. SEC-2552"
  assume_role_policy   = data.aws_iam_policy_document.support_trust.json
  max_session_duration = 3600
  tags                 = { Name = local.support_role }
}

resource "aws_iam_role_policy_attachment" "support" {
  role       = aws_iam_role.support.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AWSSupportAccess"
}
