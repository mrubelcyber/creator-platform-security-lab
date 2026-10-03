#!/usr/bin/env bash
# Lab 7 (SEC-2547): verify the Creator Platform app role is still least privilege.
# Exit 0 = PASS, exit 1 = drift found. Needs: iam:GetRole, iam:ListAttachedRolePolicies,
# iam:SimulatePrincipalPolicy on role/creator-platform-app (the CI role has exactly these).
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE=creator-platform-app
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE}"
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/cp-app-boundary"
B="arn:aws:s3:::creator-platform-training-uploads"
ADMIN='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}'
fail=0
pass() { echo "PASS  $*"; }
bad()  { echo "FAIL  $*"; fail=1; }

got=$(aws iam get-role --role-name "$ROLE" \
      --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text)
[ "$got" = "$BOUNDARY_ARN" ] && pass "permission boundary attached" || bad "boundary is '$got'"

n=$(aws iam list-attached-role-policies --role-name "$ROLE" \
    --query 'length(AttachedPolicies)' --output text)
[ "$n" = "0" ] && pass "no managed policies attached" || bad "$n managed policies attached"

expect() {  # expect <allowed|implicitDeny> <action> <resource> [admin]
  local want=$1 action=$2 res=$3 extra=()
  [ "${4:-}" = "admin" ] && extra=(--policy-input-list "$ADMIN")
  local got
  got=$(aws iam simulate-principal-policy --policy-source-arn "$ROLE_ARN" "${extra[@]}" \
        --action-names "$action" --resource-arns "$res" \
        --query 'EvaluationResults[0].EvalDecision' --output text)
  [ "$got" = "$want" ] && pass "$want  $action  $res ${4:-}" \
                       || bad "expected $want, got $got: $action $res ${4:-}"
}

expect allowed      s3:GetObject    "$B/uploads/avatar.png"
expect allowed      s3:PutObject    "$B/uploads/avatar.png"
expect implicitDeny s3:GetObject    "$B/backups/db.sqlite"
expect implicitDeny s3:GetObject    "arn:aws:s3:::some-other-bucket/file"
expect implicitDeny s3:DeleteBucket "$B"
expect implicitDeny iam:CreateUser  "*"
# Boundary proof: even with Action:* added, the ceiling holds
expect implicitDeny iam:CreateUser  "*"  admin
expect implicitDeny s3:DeleteBucket "$B" admin
expect allowed      s3:GetObject    "$B/uploads/avatar.png" admin

if [ "$fail" -eq 0 ]; then echo "App role least-privilege check: PASSED"
else echo "App role least-privilege check: FAILED"; exit 1; fi
