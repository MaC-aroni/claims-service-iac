# The two roles the migrated workloads run as. Least privilege: the service may read the
# claims table and find the MCP tool's URL; calling the MCP tool needs a separate grant from
# the MCP team (claims-mcp-server/terraform/access). The MCP tool's role may only log.
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {}
}

variable "mac_env" {
  type = string
}

variable "mac_run_id" {
  type    = string
  default = "manual"
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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  prefix  = "mac-claims-${var.mac_env}"
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "service" {
  name               = "${local.prefix}-service"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "service_logs" {
  role       = aws_iam_role.service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "service" {
  statement {
    sid       = "ReadClaims"
    actions   = ["dynamodb:GetItem"]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account}:table/${local.prefix}-claims"]
  }
  statement {
    sid       = "FindMcpTool"
    actions   = ["lambda:GetFunctionUrlConfig"]
    resources = ["arn:aws:lambda:${local.region}:${local.account}:function:${local.prefix}-mcp"]
  }
}

resource "aws_iam_role_policy" "service" {
  name   = "claims-service"
  role   = aws_iam_role.service.id
  policy = data.aws_iam_policy_document.service.json
}

resource "aws_iam_role" "mcp" {
  name               = "${local.prefix}-mcp"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "mcp_logs" {
  role       = aws_iam_role.mcp.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

output "service_role_arn" {
  value = aws_iam_role.service.arn
}

output "mcp_role_arn" {
  value = aws_iam_role.mcp.arn
}
