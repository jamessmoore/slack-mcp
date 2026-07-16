terraform {
  required_version = ">= 1.10" # S3 native state locking (use_lockfile) requires 1.10+

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_bedrockagentcore_gateway / _gateway_target (MCP server target
      # support specifically) landed in v6.21.0+ of this provider -- verify
      # against the changelog before assuming a pinned version here is
      # still current. Confirmed against CoreSample's working config.
      version = ">= 6.22"
    }
  }

  # S3 backend, same pattern as CoreSample/daily-tech-brief-bedrock: native
  # S3 conditional-write locking (use_lockfile), no DynamoDB lock table.
  # The bucket can't be created by the same config that uses it as a
  # backend (chicken-and-egg) -- bootstrap out of band before first
  # `terraform init`, same as the sibling repos.
  backend "s3" {
    bucket       = "slack-mcp-tfstate-293528978619"
    key          = "slack-mcp/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
