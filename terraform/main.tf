provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "dr"
  region = "us-west-2"
}

# Lab 0 creates no AWS application resources.
# Real infrastructure is added step-by-step in the AWS labs.
