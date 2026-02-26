"""
Get Submission Metadata Lambda Function

Retrieves submission metadata from DynamoDB with role-based authorization.
Students may only access their own submissions; Faculty and Admin may access any.
Invokes the audit-logger asynchronously on successful access.
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
AUDIT_TABLE = os.environ["AUDIT_TABLE"]
AUDIT_FUNCTION_NAME = os.environ["AUDIT_FUNCTION_NAME"]

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
dynamodb = boto3.resource("dynamodb")
submissions_table = dynamodb.Table(SUBMISSIONS_TABLE)
lambda_client = boto3.client("lambda")

# ---------------------------------------------------------------------------
# Structured JSON logging
# ---------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Replace default handler with JSON formatter
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

# Fields to strip from the response to avoid leaking internal data
INTERNAL_FIELDS = {"_version", "_ttl", "_internal_flags"}


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


def _extract_user_info(event: dict) -> dict:
    """Pull user identity fields from the Cognito authorizer claims."""
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("claims", {})
    )
    return {
        "sub": claims.get("sub", ""),
        "email": claims.get("email", ""),
        "groups": claims.get("cognito:groups", ""),
    }


def _user_in_group(user_info: dict, group_name: str) -> bool:
    """Check whether the user belongs to *group_name*.

    ``cognito:groups`` may arrive as a comma-separated string or as a
    space-separated string depending on the authorizer configuration.
    """
    groups_raw = user_info.get("groups", "")
    if not groups_raw:
        return False
    # Normalise separators
    groups = [g.strip() for g in groups_raw.replace(",", " ").split()]
    return group_name in groups


def _invoke_audit_logger(
    event_type: str,
    user_id: str,
    submission_id: str,
    ip_address: str,
    user_agent: str,
    action_metadata: dict | None = None,
) -> None:
    """Fire-and-forget invocation of the audit-logger Lambda."""
    payload = {
        "event_type": event_type,
        "user_id": user_id,
        "submission_id": submission_id,
        "ip_address": ip_address,
        "user_agent": user_agent,
        "action_metadata": action_metadata or {},
    }
    try:
        lambda_client.invoke(
            FunctionName=AUDIT_FUNCTION_NAME,
            InvocationType="Event",  # asynchronous
            Payload=json.dumps(payload),
        )
        logger.info(
            "Audit logger invoked asynchronously for submission %s",
            submission_id,
        )
    except ClientError:
        # Non-fatal – log and continue so the primary request still succeeds.
        logger.exception("Failed to invoke audit logger")


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
def lambda_handler(event, context):  # noqa: ARG001 – context unused
    """API Gateway proxy handler for GET /submissions/{id}."""
    logger.info("Received get-submission-metadata request")

    # ------------------------------------------------------------------
    # 1. Extract and validate submission_id
    # ------------------------------------------------------------------
    path_params = event.get("pathParameters") or {}
    submission_id = path_params.get("id")

    if not submission_id:
        logger.warning("Missing submission id in path parameters")
        return _build_response(400, {"error": "Missing submission id in request path"})

    logger.info("Fetching metadata for submission_id=%s", submission_id)

    # ------------------------------------------------------------------
    # 2. Extract user identity
    # ------------------------------------------------------------------
    user_info = _extract_user_info(event)
    user_sub = user_info["sub"]
    user_email = user_info["email"]

    if not user_sub:
        logger.warning("Unable to determine caller identity from authorizer claims")
        return _build_response(403, {"error": "Unable to determine caller identity"})

    # ------------------------------------------------------------------
    # 3. Retrieve the item from DynamoDB
    # ------------------------------------------------------------------
    try:
        response = submissions_table.get_item(Key={"submission_id": submission_id})
    except ClientError:
        logger.exception("DynamoDB error while fetching submission %s", submission_id)
        return _build_response(500, {"error": "Internal server error"})

    item = response.get("Item")
    if not item:
        logger.info("Submission %s not found", submission_id)
        return _build_response(404, {"error": "Submission not found"})

    # ------------------------------------------------------------------
    # 4. Authorisation
    # ------------------------------------------------------------------
    is_faculty = _user_in_group(user_info, "Faculty")
    is_admin = _user_in_group(user_info, "Admin")
    is_student = _user_in_group(user_info, "Students")

    if is_faculty or is_admin:
        logger.info(
            "Privileged access granted for user %s (email=%s)",
            user_sub,
            user_email,
        )
    elif is_student:
        if item.get("student_id") != user_sub:
            logger.warning(
                "Student %s attempted to access submission %s owned by %s",
                user_sub,
                submission_id,
                item.get("student_id"),
            )
            return _build_response(
                403,
                {"error": "You are not authorised to access this submission"},
            )
        logger.info("Student %s accessing own submission %s", user_sub, submission_id)
    else:
        logger.warning(
            "User %s does not belong to an authorised group", user_sub
        )
        return _build_response(
            403,
            {"error": "You are not authorised to access this submission"},
        )

    # ------------------------------------------------------------------
    # 5. Fire async audit event
    # ------------------------------------------------------------------
    request_context = event.get("requestContext", {})
    identity = request_context.get("identity", {})
    ip_address = identity.get("sourceIp", "unknown")
    user_agent = identity.get("userAgent", "unknown")

    _invoke_audit_logger(
        event_type="ACCESS",
        user_id=user_sub,
        submission_id=submission_id,
        ip_address=ip_address,
        user_agent=user_agent,
        action_metadata={"email": user_email, "action": "get_metadata"},
    )

    # ------------------------------------------------------------------
    # 6. Strip internal fields and return metadata
    # ------------------------------------------------------------------
    sanitised_item = {
        k: v for k, v in item.items() if k not in INTERNAL_FIELDS
    }

    logger.info("Returning metadata for submission %s", submission_id)
    return _build_response(200, sanitised_item)
