variable "aws_region" {
  description = "Region for all Lab 11 resources"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Short prefix used in every resource name"
  type        = string
  default     = "cp"
}

variable "dry_run" {
  description = "true = responder only reports what it would do. Safe default; the lab ran live (false) during 11.7."
  type        = bool
  default     = true
}

variable "protected_roles" {
  description = "Roles the responder must never contain"
  type        = list(string)
  default     = ["cp-admin-role", "cp-lab-ir-lambda-role", "cp-lab-cloudtrail-cwl-role"]
}

variable "lambda_zip_path" {
  description = "Zip built by scripts/build-ir-responder.sh, relative to this folder"
  type        = string
  default     = "../../lambda/ir-responder/build/responder.zip"
}

variable "lambda_code_sha256" {
  description = "Base64 SHA-256 of the zip (printed by scripts/build-ir-responder.sh). Empty = let Terraform compute at apply."
  type        = string
  default     = ""
}
