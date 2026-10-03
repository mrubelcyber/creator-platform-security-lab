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
  default_tags {
    tags = {
      Project   = "creator-platform"
      Lab       = "lab-07"
      Ticket    = "SEC-2547"
      ManagedBy = "terraform"
    }
  }
}
