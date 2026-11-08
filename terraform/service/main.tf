# ClaimsAdjudicationService on AWS Lambda, behind a function URL that only accepts
# AWS-signed requests (the smoke test signs with the deployer's credentials).
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
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

locals {
  prefix = "mac-claims-${var.mac_env}"
  # Built from names (not looked up) so Build can plan this before the role exists.
  role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.prefix}-service"
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/../../service"
  output_path = "${path.module}/.build/service.zip"
  excludes    = ["__pycache__"]
}

resource "aws_lambda_function" "service" {
  function_name    = "${local.prefix}-service"
  description      = "ClaimsAdjudicationService"
  role             = local.role_arn
  runtime          = "python3.12"
  handler          = "app.handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      CLAIMS_TABLE = "${local.prefix}-claims"
      MCP_FUNCTION = "${local.prefix}-mcp"
    }
  }
}

resource "aws_lambda_function_url" "service" {
  function_name      = aws_lambda_function.service.function_name
  authorization_type = "AWS_IAM"
}

output "url" {
  value = aws_lambda_function_url.service.function_url
}
