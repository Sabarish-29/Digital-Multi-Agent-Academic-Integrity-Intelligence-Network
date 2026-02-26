"""
intake-handler Lambda function.

Handles file uploads via API Gateway (multipart/form-data).
Validates, stores in S3, records metadata in DynamoDB, and triggers audit logging.
"""

import base64
import hashlib
import json
import logging
import os
import re
import uuid
from datetime import datetime, timezone

import boto3
from botocore.config import Config

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Environment variables
# ---------------------------------------------------------------------------
RAW_BUCKET = os.environ.get("RAW_BUCKET", "")
SUBMISSIONS_TABLE = os.environ.get("SUBMISSIONS_TABLE", "")
AUDIT_TABLE = os.environ.get("AUDIT_TABLE", "")
MAX_FILE_SIZE = int(os.environ.get("MAX_FILE_SIZE", "52428800"))  # 50 MiB default
AUDIT_FUNCTION_NAME = os.environ.get("AUDIT_FUNCTION_NAME", "")

# ---------------------------------------------------------------------------
# Allowed file extensions
# ---------------------------------------------------------------------------
ALLOWED_EXTENSIONS = {
    ".pdf", ".docx", ".txt", ".py", ".java", ".cpp",
    ".c", ".js", ".html", ".css", ".ipynb", ".tex",
}

# ---------------------------------------------------------------------------
# CORS headers included in every response
# ---------------------------------------------------------------------------
CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
}

# ---------------------------------------------------------------------------
# AWS clients (re-used across warm invocations)
# ---------------------------------------------------------------------------
_retry_config = Config(retries={"max_attempts": 3, "mode": "standard"})
s3_client = boto3.client("s3", config=_retry_config)
dynamodb = boto3.resource("dynamodb", config=_retry_config)
lambda_client = boto3.client("lambda", config=_retry_config)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_response(status_code: int, body: dict) -> dict:
    """Return an API-Gateway-compatible response dict."""
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": json.dumps(body),
    }


def _parse_multipart(content_type: str, body_bytes: bytes) -> dict:
    """Parse a multipart/form-data body and return a dict of parts.

    Each key maps to a dict with:
      - ``value``   : bytes  (raw content of the part)
      - ``filename``: str or None  (present only for file parts)
    """
    # Extract boundary from Content-Type header
    match = re.search(r"boundary=([^\s;]+)", content_type)
    if not match:
        raise ValueError("Missing boundary in Content-Type header")

    boundary = match.group(1).strip('"').strip("'")
    # The actual delimiter in the body is prefixed with "--"
    delimiter = f"--{boundary}".encode()

    parts = body_bytes.split(delimiter)
    parsed: dict = {}

    for part in parts:
        # Skip the preamble and the closing delimiter
        if not part or part.strip() in (b"", b"--", b"--\r\n"):
            continue

        # Separate headers from body (split on first double CRLF)
        if b"\r\n\r\n" in part:
            raw_headers, raw_body = part.split(b"\r\n\r\n", 1)
        elif b"\n\n" in part:
            raw_headers, raw_body = part.split(b"\n\n", 1)
        else:
            continue

        # Strip trailing \r\n from the body (part boundary artefact)
        if raw_body.endswith(b"\r\n"):
            raw_body = raw_body[:-2]

        header_text = raw_headers.decode("utf-8", errors="replace")

        # Extract field name
        name_match = re.search(r'name="([^"]+)"', header_text)
        if not name_match:
            continue
        field_name = name_match.group(1)

        # Extract optional filename
        filename_match = re.search(r'filename="([^"]*)"', header_text)
        filename = filename_match.group(1) if filename_match else None

        parsed[field_name] = {
            "value": raw_body,
            "filename": filename,
        }

    return parsed


def _get_extension(filename: str) -> str:
    """Return the lower-cased file extension including the dot."""
    idx = filename.rfind(".")
    if idx == -1:
        return ""
    return filename[idx:].lower()


def _sha256(data: bytes) -> str:
    """Return hex-encoded SHA-256 digest."""
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------

def lambda_handler(event, context):  # noqa: C901 – complexity acceptable for a Lambda entry-point
    """AWS Lambda entry point."""

    # Handle CORS preflight
    http_method = event.get("httpMethod", "")
    if http_method == "OPTIONS":
        return _build_response(200, {"message": "OK"})

    try:
        # ---------------------------------------------------------------
        # 1. Extract user info from Cognito authorizer claims
        # ---------------------------------------------------------------
        claims = (
            event.get("requestContext", {})
            .get("authorizer", {})
            .get("claims", {})
        )
        user_id = claims.get("sub", "anonymous")
        email = claims.get("email", "unknown")

        logger.info(json.dumps({
            "message": "Intake request received",
            "user_id": user_id,
            "email": email,
            "http_method": http_method,
        }))

        # ---------------------------------------------------------------
        # 2. Decode body
        # ---------------------------------------------------------------
        body_raw = event.get("body", "")
        if not body_raw:
            return _build_response(400, {"error": "Empty request body"})

        is_base64 = event.get("isBase64Encoded", False)
        if is_base64:
            body_bytes = base64.b64decode(body_raw)
        else:
            body_bytes = body_raw.encode("utf-8") if isinstance(body_raw, str) else body_raw

        # ---------------------------------------------------------------
        # 3. Parse multipart form data
        # ---------------------------------------------------------------
        headers = event.get("headers", {}) or {}
        # API Gateway may normalise header names to lower-case
        content_type = headers.get("Content-Type") or headers.get("content-type") or ""

        if "multipart/form-data" not in content_type:
            return _build_response(400, {
                "error": "Content-Type must be multipart/form-data",
            })

        try:
            parts = _parse_multipart(content_type, body_bytes)
        except ValueError as exc:
            logger.warning(json.dumps({"message": "Multipart parse error", "error": str(exc)}))
            return _build_response(400, {"error": f"Malformed multipart body: {exc}"})

        # ---------------------------------------------------------------
        # 4. Validate required fields
        # ---------------------------------------------------------------
        if "file" not in parts or parts["file"].get("filename") is None:
            return _build_response(400, {"error": "Missing required field: file"})

        for field in ("student_id", "course_id", "section_id"):
            if field not in parts:
                return _build_response(400, {"error": f"Missing required field: {field}"})

        file_content: bytes = parts["file"]["value"]
        original_filename: str = parts["file"]["filename"]
        student_id: str = parts["student_id"]["value"].decode("utf-8").strip()
        course_id: str = parts["course_id"]["value"].decode("utf-8").strip()
        section_id: str = parts["section_id"]["value"].decode("utf-8").strip()

        if not student_id or not course_id or not section_id:
            return _build_response(400, {"error": "student_id, course_id, and section_id must not be empty"})

        # ---------------------------------------------------------------
        # 5. Validate file extension
        # ---------------------------------------------------------------
        extension = _get_extension(original_filename)
        if extension not in ALLOWED_EXTENSIONS:
            return _build_response(400, {
                "error": f"Invalid file type '{extension}'. Allowed: {sorted(ALLOWED_EXTENSIONS)}",
            })

        # ---------------------------------------------------------------
        # 6. Validate file size
        # ---------------------------------------------------------------
        file_size = len(file_content)
        if file_size > MAX_FILE_SIZE:
            return _build_response(413, {
                "error": f"File too large ({file_size} bytes). Maximum allowed: {MAX_FILE_SIZE} bytes",
            })

        # ---------------------------------------------------------------
        # 7. Generate identifiers and hash
        # ---------------------------------------------------------------
        submission_id = str(uuid.uuid4())
        sha256_hash = _sha256(file_content)
        upload_timestamp = datetime.now(timezone.utc).isoformat()

        s3_key = f"submissions/{student_id}/{submission_id}/{original_filename}"

        logger.info(json.dumps({
            "message": "Processing submission",
            "submission_id": submission_id,
            "student_id": student_id,
            "file_name": original_filename,
            "file_size": file_size,
            "sha256_hash": sha256_hash,
        }))

        # ---------------------------------------------------------------
        # 8. Upload to S3
        # ---------------------------------------------------------------
        try:
            s3_client.put_object(
                Bucket=RAW_BUCKET,
                Key=s3_key,
                Body=file_content,
                ContentType="application/octet-stream",
                Metadata={
                    "submission_id": submission_id,
                    "student_id": student_id,
                    "sha256": sha256_hash,
                },
            )
        except Exception:
            logger.exception("S3 upload failed")
            return _build_response(500, {"error": "Failed to upload file to storage"})

        # ---------------------------------------------------------------
        # 9. Write metadata to DynamoDB
        # ---------------------------------------------------------------
        try:
            table = dynamodb.Table(SUBMISSIONS_TABLE)
            table.put_item(Item={
                "submission_id": submission_id,
                "student_id": student_id,
                "course_id": course_id,
                "section_id": section_id,
                "file_path": f"s3://{RAW_BUCKET}/{s3_key}",
                "file_name": original_filename,
                "file_size": file_size,
                "file_type": extension,
                "sha256_hash": sha256_hash,
                "upload_timestamp": upload_timestamp,
                "status": "uploaded",
                "user_id": user_id,
                "email": email,
            })
        except Exception:
            logger.exception("DynamoDB write failed")
            return _build_response(500, {"error": "Failed to record submission metadata"})

        # ---------------------------------------------------------------
        # 10. Invoke audit-logger asynchronously
        # ---------------------------------------------------------------
        if AUDIT_FUNCTION_NAME:
            try:
                audit_payload = {
                    "event_type": "UPLOAD",
                    "submission_id": submission_id,
                    "student_id": student_id,
                    "course_id": course_id,
                    "section_id": section_id,
                    "file_name": original_filename,
                    "file_size": file_size,
                    "sha256_hash": sha256_hash,
                    "upload_timestamp": upload_timestamp,
                    "user_id": user_id,
                    "email": email,
                }
                lambda_client.invoke(
                    FunctionName=AUDIT_FUNCTION_NAME,
                    InvocationType="Event",
                    Payload=json.dumps(audit_payload),
                )
            except Exception:
                # Audit logging failure is non-fatal; do not block the upload
                logger.exception("Failed to invoke audit-logger")

        # ---------------------------------------------------------------
        # 11. Return success response
        # ---------------------------------------------------------------
        logger.info(json.dumps({
            "message": "Submission processed successfully",
            "submission_id": submission_id,
        }))

        return _build_response(200, {
            "message": "File uploaded successfully",
            "submission_id": submission_id,
            "file_name": original_filename,
            "file_size": file_size,
            "sha256_hash": sha256_hash,
            "upload_timestamp": upload_timestamp,
            "status": "uploaded",
        })

    except Exception:
        logger.exception("Unhandled exception in intake-handler")
        return _build_response(500, {"error": "Internal server error"})
