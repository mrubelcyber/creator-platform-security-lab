# Password policy and support role moved to terraform/baseline at Lab 12 cleanup (SEC-2552).

# IAM.2 / CIS 1.14 - adopt (import) the user-attached policy, then retire it in phase 2
import {
  for_each = var.legacy_change_password_users
  to       = aws_iam_user_policy_attachment.legacy_change_password[each.key]
  id       = "${each.key}/${local.change_password_policy_arn}"
}

resource "aws_iam_user_policy_attachment" "legacy_change_password" {
  #checkov:skip=CKV_AWS_40:Temporary - adopts the existing user-attached IAMUserChangePassword (IAM.2) so phase 2 can detach it via a reviewed plan; with the list empty no attachment exists (SEC-2552)
  for_each   = var.legacy_change_password_users
  user       = each.key
  policy_arn = local.change_password_policy_arn
}
