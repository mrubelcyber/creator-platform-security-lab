# ---------------------------------------------------------------
# Lab 9 (SEC-2549) - Part C: every new disk is encrypted (Finding 4)
# ---------------------------------------------------------------

# Default key stays alias/aws/ebs on purpose (documented decision):
# disks must not depend on a lab key that we may delete.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}
