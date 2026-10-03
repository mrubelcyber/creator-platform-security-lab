variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "uploads_bucket_name" {
  description = "S3 bucket the app reads and writes (defined in Lab 4)"
  type        = string
  default     = "creator-platform-training-uploads"
}

variable "uploads_prefix" {
  description = "Only object keys under this prefix are allowed"
  type        = string
  default     = "uploads/"
}
