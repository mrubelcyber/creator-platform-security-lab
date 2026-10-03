variable "github_repo" {
  description = "Only this GitHub repo may assume the CI role"
  type        = string
  default     = "mrubelcyber/creator-platform-security-lab"
}

variable "github_branch" {
  description = "Only workflow runs on this branch may assume the CI role"
  type        = string
  default     = "main"
}

# GitHub's OIDC identity provider (free)
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Trust: only this repo, only the main branch, only tokens meant for AWS STS
data "aws_iam_policy_document" "ci_trust" {
  statement {
    sid     = "GitHubActionsThisRepoMainOnly"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

# Ceiling for the CI role: read/simulate Creator Platform roles only
data "aws_iam_policy_document" "ci_boundary" {
  statement {
    sid = "ReadAndSimulateCreatorPlatformRolesOnly"
    actions = [
      "iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:SimulatePrincipalPolicy"
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/creator-platform-*"]
  }
}

resource "aws_iam_policy" "ci_boundary" {
  name        = "cp-ci-boundary"
  description = "Permission boundary (ceiling) for the GitHub Actions CI role"
  policy      = data.aws_iam_policy_document.ci_boundary.json
}

# What CI actually gets: check the app role only
data "aws_iam_policy_document" "ci_permissions" {
  statement {
    sid = "CheckAppRoleLeastPrivilege"
    actions = [
      "iam:GetRole", "iam:ListRolePolicies", "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:SimulatePrincipalPolicy"
    ]
    resources = [aws_iam_role.app.arn]
  }
}

resource "aws_iam_role" "ci" {
  name                 = "creator-platform-ci"
  description          = "GitHub Actions OIDC role: verify app role least privilege"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust.json
  permissions_boundary = aws_iam_policy.ci_boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "ci" {
  name   = "creator-platform-ci-iam-check"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_permissions.json
}

output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}
