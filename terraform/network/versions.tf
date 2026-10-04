terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource in this folder gets these tags automatically.
  # Written once here, so no more tag typos.
  default_tags {
    tags = {
      Project   = "creator-platform"
      Lab       = "lab-08"
      Ticket    = "SEC-2548"
      ManagedBy = "terraform"
    }
  }
}
