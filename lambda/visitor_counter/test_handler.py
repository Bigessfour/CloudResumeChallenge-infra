"""Unit tests for the visitor counter Lambda (CRC step 11).

Strategy: use `moto` to mock DynamoDB so tests run hermetically with zero AWS
calls and zero cost. Env vars come from `conftest.py`.

Each test asks for the `handler` fixture, which yields a freshly-reloaded
module bound to a fresh moto-mocked table — guaranteeing test isolation.
"""

import importlib
import json
import os

import boto3
import pytest
from moto import mock_aws


ALLOWED_ORIGIN = "https://stephenmckitrick.com"


@pytest.fixture
def handler():
    """Yield the handler module with a moto-mocked DynamoDB table."""
    with mock_aws():
        ddb = boto3.resource("dynamodb", region_name=os.environ["AWS_DEFAULT_REGION"])
        ddb.create_table(
            TableName=os.environ["TABLE_NAME"],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        # Reload so the module-level `dynamodb` and `table` re-bind to the mocked client.
        import handler as handler_module  # noqa: WPS433 — late import is intentional

        importlib.reload(handler_module)
        yield handler_module


def _browser_event(**overrides):
    headers = {
        "origin": ALLOWED_ORIGIN,
        "referer": f"{ALLOWED_ORIGIN}/",
        "user-agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "sec-fetch-site": "cross-site",
        "sec-fetch-mode": "cors",
    }
    headers.update(overrides.get("headers") or {})
    event = {"headers": headers}
    event.update({k: v for k, v in overrides.items() if k != "headers"})
    return event


def _options_event():
    return {"requestContext": {"http": {"method": "OPTIONS"}}}


# ──────────────────────────────────────────────────────────────────────────
# OPTIONS / preflight
# ──────────────────────────────────────────────────────────────────────────


def test_options_preflight_returns_200(handler):
    response = handler.lambda_handler(_options_event(), context=None)

    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"ok": True}


def test_options_preflight_does_not_increment_counter(handler):
    # 5 preflights then a real request — count should still be 1.
    for _ in range(5):
        handler.lambda_handler(_options_event(), context=None)

    real = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(real["body"])["count"] == 1, (
        "CORS preflights must not increment the visitor counter"
    )


# ──────────────────────────────────────────────────────────────────────────
# Normal request path
# ──────────────────────────────────────────────────────────────────────────


def test_first_request_returns_count_one(handler):
    response = handler.lambda_handler(_browser_event(), context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body == {"count": 1}
    assert isinstance(body["count"], int), (
        "count must be a JSON-safe int, not a DynamoDB Decimal"
    )


def test_count_increments_atomically_across_calls(handler):
    counts = [
        json.loads(handler.lambda_handler(_browser_event(), context=None)["body"])["count"]
        for _ in range(5)
    ]

    assert counts == [1, 2, 3, 4, 5], (
        f"Expected sequential ADD increments [1..5], got {counts}"
    )


# ──────────────────────────────────────────────────────────────────────────
# Bot / scraper rejection
# ──────────────────────────────────────────────────────────────────────────


def test_rejects_missing_origin_and_referer_without_increment(handler):
    response = handler.lambda_handler(
        {
            "headers": {
                "user-agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
            }
        },
        context=None,
    )

    assert response["statusCode"] == 403
    assert json.loads(response["body"]) == {"error": "forbidden"}

    follow_up = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(follow_up["body"])["count"] == 1


def test_rejects_empty_user_agent_without_increment(handler):
    response = handler.lambda_handler(
        _browser_event(headers={"user-agent": "", "origin": ALLOWED_ORIGIN}),
        context=None,
    )

    assert response["statusCode"] == 403

    follow_up = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(follow_up["body"])["count"] == 1


def test_rejects_known_scraper_user_agents_without_increment(handler):
    for user_agent in ("curl/8.5.0", "python-requests/2.31.0", "Googlebot/2.1"):
        response = handler.lambda_handler(
            _browser_event(headers={"user-agent": user_agent}),
            context=None,
        )
        assert response["statusCode"] == 403, user_agent

    follow_up = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(follow_up["body"])["count"] == 1


def test_rejects_spoofed_origin_without_sec_fetch_headers(handler):
    response = handler.lambda_handler(
        {
            "headers": {
                "origin": ALLOWED_ORIGIN,
                "user-agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
            }
        },
        context=None,
    )

    assert response["statusCode"] == 403
    follow_up = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(follow_up["body"])["count"] == 1


def test_rejects_chrome_devtools_headless_without_increment(handler):
    response = handler.lambda_handler(
        _browser_event(
            headers={
                "user-agent": (
                    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                    "(KHTML, like Gecko) HeadlessChrome/120.0.0.0 Safari/537.36"
                )
            }
        ),
        context=None,
    )

    assert response["statusCode"] == 403
    follow_up = handler.lambda_handler(_browser_event(), context=None)
    assert json.loads(follow_up["body"])["count"] == 1


def test_accepts_valid_referer_when_origin_missing(handler):
    response = handler.lambda_handler(
        {
            "headers": {
                "referer": f"{ALLOWED_ORIGIN}/resume",
                "user-agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                "sec-fetch-site": "cross-site",
                "sec-fetch-mode": "cors",
            }
        },
        context=None,
    )

    assert response["statusCode"] == 200
    assert json.loads(response["body"]) == {"count": 1}


# ──────────────────────────────────────────────────────────────────────────
# Response shape
# ──────────────────────────────────────────────────────────────────────────


def test_response_headers_set_json_and_no_store(handler):
    response = handler.lambda_handler(_browser_event(), context=None)

    assert response["headers"]["Content-Type"] == "application/json"
    assert response["headers"]["Cache-Control"] == "no-store", (
        "Counter responses must not be cached by intermediaries"
    )


def test_response_body_is_valid_json_string(handler):
    response = handler.lambda_handler(_browser_event(), context=None)

    # If body is not a string, API Gateway integration will 502.
    assert isinstance(response["body"], str)
    json.loads(response["body"])  # raises on malformed JSON


def test__response_helper_serializes_arbitrary_body():
    """The private _response helper should JSON-encode any dict body."""
    import handler as handler_module

    out = handler_module._response(418, {"teapot": True, "tea": ["earl grey", "hot"]})

    assert out["statusCode"] == 418
    assert json.loads(out["body"]) == {"teapot": True, "tea": ["earl grey", "hot"]}
