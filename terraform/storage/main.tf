# The claims table ClaimsAdjudicationService reads (DynamoDB, the landing zone's approved
# key-value store). claims-db-migrate loads it; undo deletes the table.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {} # MaC supplies bucket, key and locking per environment and step
}

variable "mac_env" {
  description = "rehearsal or production; every name includes it so the two never collide"
  type        = string
}

variable "mac_run_id" {
  description = "The MaC deployment ID that last changed these resources"
  type        = string
  default     = "manual"
}

provider "aws" {
  default_tags {
    tags = {
      "mac:migration"     = "claims-adjudication-onprem-to-aws"
      "mac:env"           = var.mac_env
      "mac:deployment-id" = var.mac_run_id
      "managed-by"        = "MaC"
      "owner-team"        = "claims-platform"
    }
  }
}

resource "aws_dynamodb_table" "claims" {
  name         = "mac-claims-${var.mac_env}-claims"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "claim_id"

  attribute {
    name = "claim_id"
    type = "S"
  }
}

output "table_name" {
  value = aws_dynamodb_table.claims.name
}
