import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "service"))

import app  # noqa: E402

CLAIM = {"claim_id": "CLM-1001", "member_id": "M-20001", "service_date": "2024-01-05", "amount": "120.50"}


def eligible(member, day):
    return {"eligible": True, "reason": "active coverage"}


def test_approves_an_eligible_claim_under_the_limit():
    result = app.adjudicate(CLAIM, eligible)
    assert result == {"claim_id": "CLM-1001", "decision": "approved", "amount": "120.50",
                      "service_date": "2024-01-05", "reason": "eligible and within the auto-approval limit"}


def test_large_claims_go_to_review_and_ineligible_ones_are_denied():
    assert app.adjudicate({**CLAIM, "amount": "9000"}, eligible)["decision"] == "pending_review"
    denied = app.adjudicate(CLAIM, lambda m, d: {"eligible": False, "reason": "not covered"})
    assert denied["decision"] == "denied" and denied["reason"] == "not covered"


def test_passes_the_iso_date_to_the_eligibility_check():
    seen = []
    app.adjudicate(CLAIM, lambda m, d: seen.append((m, d)) or {"eligible": True, "reason": ""})
    assert seen == [("M-20001", "2024-01-05")]


def test_health_and_routing():
    event = {"rawPath": "/health", "requestContext": {"http": {"method": "GET"}}}
    assert json.loads(app.handler(event, None)["body"]) == {"status": "ok"}
    assert app.handler({"rawPath": "/nope", "requestContext": {"http": {"method": "GET"}}}, None)["statusCode"] == 404


def test_claim_id_is_required():
    event = {"rawPath": "/adjudicate", "requestContext": {"http": {"method": "POST"}}, "body": "{}"}
    assert app.handler(event, None)["statusCode"] == 400


@pytest.mark.parametrize("amount", ["0", "5000", "4999.99"])
def test_limit_boundary(amount):
    assert app.adjudicate({**CLAIM, "amount": amount}, eligible)["decision"] == "approved"
