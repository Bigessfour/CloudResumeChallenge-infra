"""Increment and return the resume site visitor count (Cloud Resume Challenge)."""

import json
import os
import re

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
COUNTER_KEY = os.environ.get("COUNTER_KEY", "visitor-counter")
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

# Obvious non-browser clients; keep the list small and maintainable.
BOT_USER_AGENT = re.compile(
    r"(bot|crawler|spider|scrapy|curl/|wget/|python-requests|httpclient|"
    r"httpx/|aiohttp/|headless|selenium|phantomjs|puppeteer|playwright|"
    r"slurp|scan|fetcher|go-http-client|java/|libwww|okhttp)",
    re.IGNORECASE,
)


def lambda_handler(event, context):
    del context  # unused

    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return _response(200, {"ok": True})

    if not _is_allowed_request(event):
        return _response(403, {"error": "forbidden"})

    result = table.update_item(
        Key={"id": COUNTER_KEY},
        UpdateExpression="ADD hits :incr",
        ExpressionAttributeValues={":incr": 1},
        ReturnValues="UPDATED_NEW",
    )

    count = int(result["Attributes"]["hits"])
    return _response(200, {"count": count})


def _is_allowed_request(event):
    """Accept first-party CORS browser traffic; reject scraper-style calls."""
    headers = {key.lower(): (value or "") for key, value in (event.get("headers") or {}).items()}
    user_agent = headers.get("user-agent", "").strip()
    return bool(
        ALLOWED_ORIGINS
        and user_agent
        and not BOT_USER_AGENT.search(user_agent)
        and headers.get("sec-fetch-site", "").lower()
        in {"cross-site", "same-origin", "same-site"}
        and headers.get("sec-fetch-mode", "").lower() in {"cors", "navigate"}
        and headers.get("origin") in ALLOWED_ORIGINS
    )


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body),
    }
