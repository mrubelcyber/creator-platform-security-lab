terraform {
  required_version = ">= 1.11.0" # write-only secrets (ssm.tf) need 1.11+

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
  default_tags {
    tags = {
      Project   = "creator-platform"
      Lab       = "lab-09"
      Ticket    = "SEC-2549"
      ManagedBy = "terraform"
    }
  }
}
