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
  # Do not put access keys or session tokens into Terraform files.
  region = var.aws_region
}
