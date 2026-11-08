# claims-service-iac

**ClaimsAdjudicationService** and its AWS infrastructure, owned by claims-platform.

| Path | Used by MaC step | What it does |
|---|---|---|
| `terraform/storage` | `provision_storage` | The claims table (DynamoDB) |
| `terraform/iam` | `provision_iam` | The service's and the MCP tool's roles, least privilege |
| `terraform/service` | `deploy_service` | The service on Lambda, behind an AWS_IAM function URL |
| `service/` | | The service: `POST /adjudicate` reads a claim, asks the Claims MCP tool about eligibility, decides |

## Naming contract (shared by all four repos)

MaC passes `MAC_ENV` (`rehearsal` or `production`) to every step, and every resource name
includes it, so a rehearsal never touches production:

| Resource | Name |
|---|---|
| Claims table (DynamoDB) | `mac-claims-<env>-claims` |
| Service role / Lambda | `mac-claims-<env>-service` |
| MCP tool role / Lambda | `mac-claims-<env>-mcp` |

Every AWS resource is tagged `mac:env`, `mac:migration` and `mac:deployment-id` (the MaC run
that last changed it), so you can see in the AWS console which deployment made what.

## How it runs

MaC checks this repo's `main` out at the exact commit Build locked and runs it; see
[MaC's runner docs](https://github.com/MaC-aroni/deployed-on-a-prayer/blob/main/docs/runner.md).
Build only runs code whose CI passed and that reached `main` through an approved pull request,
so **every change here goes through a reviewed PR**.

Local checks: `pip install -r requirements-dev.txt && python -m pytest`
