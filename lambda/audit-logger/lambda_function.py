"""
Audit Logger Lambda Function

Writes structured audit events to the DynamoDB audit_log table.
This function is invoked **asynchronously** by other Lambdas and does not
return HTTP responses.  It uses exponential-backoff retry configuration
for DynamoDB writes.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AUDIT_TABLE = os.environ["AUDIT_TABLE"]

# Valid event types that the logger will accept
VALID_EVENT_TYPES = {"UPLOAD", "ACCESS", "DOWNLOAD", "DELETE"}

# ---------------------------------------------------------------------------
# AWS clients – exponential backoff via boto3 retry config
# ---------------------------------------------------------------------------
_retry_config = Config(
    retries={
        "max_attempts": 5,
        "mode": "adaptive",  # adaptive = exponential backoff + rate limiting
    }
)

dynamodb = boto3.resource("dynamodb", config=_retry_config)
audit_table = dynamodb.Table(AUDIT_TABLE)

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
# Handler
# ---------------------------------------------------------------------------
def lambda_handler(event, context):  # noqa: ARG001 – context unused
    """Process an incoming audit event and persist it to DynamoDB.

    Expected *event* payload::

        {
            "event_type": "UPLOAD" | "ACCESS" | "DOWNLOAD" | "DELETE",
            "user_id": "<cognito-sub>",
            "submission_id": "<uuid>",
            "ip_address": "<source-ip>",
            "user_agent": "<user-agent-string>",
            "action_metadata": { ... }   # optional dict with extra context
        }

    Returns::

        {"status": "logged", "audit_id": "<generated-uuid>"}
    """
    logger.info("Audit logger invoked with event: %s", json.dumps(event, default=str))

    # ------------------------------------------------------------------
    # 1. Extract and validate fields
    # ------------------------------------------------------------------
    event_type = event.get("event_type", "")
    user_id = event.get("user_id", "")
    submission_id = event.get("submission_id", "")
    ip_address = event.get("ip_address", "unknown")
    user_agent = event.get("user_agent", "unknown")
    action_metadata = event.get("action_metadata") or {}

    if event_type not in VALID_EVENT_TYPES:
        logger.error(
            "Invalid or missing event_type: '%s'. Must be one of %s",
            event_type,
            VALID_EVENT_TYPES,
        )
        return {
            "status": "error",
            "error": f"Invalid event_type '{event_type}'. Must be one of {sorted(VALID_EVENT_TYPES)}",
        }

    if not user_id:
        logger.error("Missing required field: user_id")
        return {"status": "error", "error": "Missing required field: user_id"}

    if not submission_id:
        logger.error("Missing required field: submission_id")
        return {"status": "error", "error": "Missing required field: submission_id"}

    # ------------------------------------------------------------------
    # 2. Build the audit record
    # ------------------------------------------------------------------
    audit_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    audit_item = {
        "audit_id": audit_id,
        "event_type": event_type,
        "user_id": user_id,
        "submission_id": submission_id,
        "timestamp": timestamp,
        "ip_address": ip_address,
        "user_agent": user_agent,
        "action_metadata": action_metadata,
    }

    # ------------------------------------------------------------------
    # 3. Persist to DynamoDB (retries handled by boto3 adaptive config)
    # ------------------------------------------------------------------
    try:
        audit_table.put_item(Item=audit_item)
        logger.info(
            "Audit event written: audit_id=%s event_type=%s submission_id=%s",
            audit_id,
            event_type,
            submission_id,
        )
    except ClientError:
        logger.exception(
            "Failed to write audit event for submission %s after retries",
            submission_id,
        )
        return {
            "status": "error",
            "error": "Failed to write audit event to DynamoDB",
        }

    return {"status": "logged", "audit_id": audit_id}
