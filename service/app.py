"""ClaimsAdjudicationService on AWS Lambda.

POST /adjudicate {"claim_id": "CLM-1001"} reads the claim from DynamoDB, asks the Claims MCP
tool whether the member was covered on the date of service, and returns a decision.
GET /health says it's up.
"""

import base64
import json
import os
from datetime import datetime
from decimal import Decimal

import boto3

from mcp_client import McpClient, McpError

TABLE = os.environ.get("CLAIMS_TABLE", "")
MCP_FUNCTION = os.environ.get("MCP_FUNCTION", "")
REGION = os.environ.get("AWS_REGION", "us-east-1")
AUTO_APPROVE_LIMIT = Decimal("5000")

_mcp: McpClient | None = None


def mcp() -> McpClient:
    global _mcp
    if _mcp is None:
        url = boto3.client("lambda").get_function_url_config(FunctionName=MCP_FUNCTION)["FunctionUrl"]
        _mcp = McpClient(url, REGION)
        _mcp.initialize("claims-adjudication-service")
    return _mcp


def adjudicate(claim: dict, eligibility) -> dict:
    """The business rule. eligibility(member_id, iso_date) -> dict from the MCP tool."""
    service_date = datetime.strptime(claim["service_date"], "%Y-%m-%d").date()
    amount = Decimal(str(claim["amount"]))
    check = eligibility(claim["member_id"], service_date.isoformat())
    if not check["eligible"]:
        decision, reason = "denied", check["reason"]
    elif amount > AUTO_APPROVE_LIMIT:
        decision, reason = "pending_review", f"amount over {AUTO_APPROVE_LIMIT} needs manual review"
    else:
        decision, reason = "approved", "eligible and within the auto-approval limit"
    return {"claim_id": claim["claim_id"], "decision": decision, "reason": reason,
            "amount": str(amount), "service_date": service_date.isoformat()}


def handler(event, context):
    http = event.get("requestContext", {}).get("http", {})
    path, method = event.get("rawPath", "/"), http.get("method", "GET")
    if path == "/health":
        return _json(200, {"status": "ok"})
    if path != "/adjudicate" or method != "POST":
        return _json(404, {"error": "not found"})

    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    claim_id = json.loads(raw).get("claim_id")
    if not claim_id:
        return _json(400, {"error": "claim_id is required"})

    item = boto3.resource("dynamodb").Table(TABLE).get_item(Key={"claim_id": claim_id}).get("Item")
    if item is None:
        return _json(404, {"error": f"no claim {claim_id}"})
    try:
        result = adjudicate(item, lambda member, day: mcp().call_tool(
            "check_eligibility", {"member_id": member, "service_date": day}))
    except ValueError as e:  # bad data in the claim record
        print(f"adjudication failed for {claim_id}: {e}")
        return _json(500, {"error": f"claim {claim_id} has bad data: {e}"})
    except McpError as e:
        print(f"eligibility check failed for {claim_id}: {e}")
        return _json(502, {"error": str(e)})
    return _json(200, result)


def _json(status: int, body: dict) -> dict:
    return {"statusCode": status, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}
