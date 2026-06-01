"""Increment and return the resume site visitor count (Cloud Resume Challenge)."""

import json
import os

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
COUNTER_KEY = os.environ.get("COUNTER_KEY", "visitor-counter")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    del context  # unused

    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return _response(200, {"ok": True})

    result = table.update_item(
        Key={"id": COUNTER_KEY},
        UpdateExpression="ADD hits :incr",
        ExpressionAttributeValues={":incr": 1},
        ReturnValues="UPDATED_NEW",
    )

    count = int(result["Attributes"]["hits"])
    return _response(200, {"count": count})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body),
    }
