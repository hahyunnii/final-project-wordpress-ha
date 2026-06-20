terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # AWS Academy temporary credentials are read from environment variables.
  # Never put access keys or session tokens in Terraform files.
  region = var.aws_region
}
