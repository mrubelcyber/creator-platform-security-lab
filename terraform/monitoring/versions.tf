terraform {
  required_version = ">= 1.11.0"

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
      Lab       = "lab-10"
      Ticket    = "SEC-2550"
      ManagedBy = "terraform"
    }
  }
}
