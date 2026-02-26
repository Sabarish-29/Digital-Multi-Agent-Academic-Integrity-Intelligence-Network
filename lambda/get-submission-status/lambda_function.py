"""
Get Submission Status Lambda Function

Lightweight Lambda that returns only the processing status for a given
submission.  Authorization is handled at the API Gateway layer via the
Cognito authorizer, so no per-role checks are performed here.
"""

import json
import logging
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SUBMISSIONS_TABLE = os.environ["SUBMISSIONS_TABLE"]

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
dynamodb = boto3.resource("dynamodb")
submissions_table = dynamodb.Table(SUBMISSIONS_TABLE)

# ---------------------------------------------------------------------------
# Structured JSON logging
# ---------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

for handler in logger.handlers:
    logger.removeHandler(handler)

json_handler = logging.StreamHandler()


class JSONFormatter(logging.Formatter):
    """Emit each log record as a single JSON line."""

    def format(self, record):
        log_entry = {
            "level": record.levelname,
            "message": record.getMessage(),
            "function": record.funcName,
            "timestamp": self.formatTime(record, self.datefmt),
        }
        if record.exc_info and record.exc_info[0] is not None:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry, default=str)


json_handler.setFormatter(JSONFormatter())
logger.addHandler(json_handler)

# ---------------------------------------------------------------------------
# CORS headers included in every response
# ---------------------------------------------------------------------------
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Content-Type": "application/json",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
class DecimalEncoder(json.JSONEncoder):
    """Handle Decimal values returned by DynamoDB."""

    def default(self, o):
        if isinstance(o, Decimal):
            if o % 1 == 0:
                return int(o)
            return float(o)
        return super().default(o)


def _build_response(status_code: int, body: dict) -> dict:
    """Return a properly formatted API Gateway proxy response."""
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body, cls=DecimalEncoder),
    }


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
def lambda_handler(event, context):  # noqa: ARG001 – context unused
    """API Gateway proxy handler for GET /submissions/{id}/status."""
    logger.info("Received get-submission-status request")

    # ------------------------------------------------------------------
    # 1. Extract and validate submission_id
    # ------------------------------------------------------------------
    path_params = event.get("pathParameters") or {}
    submission_id = path_params.get("id")

    if not submission_id:
        logger.warning("Missing submission id in path parameters")
        return _build_response(400, {"error": "Missing submission id in request path"})

    logger.info("Fetching status for submission_id=%s", submission_id)

    # ------------------------------------------------------------------
    # 2. Query DynamoDB – project only the fields we need
    # ------------------------------------------------------------------
    try:
        response = submissions_table.get_item(
            Key={"submission_id": submission_id},
            ProjectionExpression="submission_id, #s, upload_timestamp",
            ExpressionAttributeNames={"#s": "status"},  # status is reserved
        )
    except ClientError:
        logger.exception(
            "DynamoDB error while fetching status for submission %s",
            submission_id,
        )
        return _build_response(500, {"error": "Internal server error"})

    item = response.get("Item")
    if not item:
        logger.info("Submission %s not found", submission_id)
        return _build_response(404, {"error": "Submission not found"})

    # ------------------------------------------------------------------
    # 3. Return the status payload
    # ------------------------------------------------------------------
    result = {
        "submission_id": item.get("submission_id"),
        "status": item.get("status"),
        "upload_timestamp": item.get("upload_timestamp"),
    }

    logger.info(
        "Returning status for submission %s: %s",
        submission_id,
        result.get("status"),
    )
    return _build_response(200, result)
