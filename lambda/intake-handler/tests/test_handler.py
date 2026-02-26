"""
Unit tests for the intake-handler Lambda function.

Uses moto to mock AWS services (S3, DynamoDB, Lambda).
"""

import base64
import hashlib
import json
import os
import uuid
from unittest.mock import patch

import boto3
import pytest
from moto import mock_aws

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
RAW_BUCKET = "test-raw-bucket"
SUBMISSIONS_TABLE = "test-submissions"
AUDIT_TABLE = "test-audit"
AUDIT_FUNCTION_NAME = "test-audit-logger"
BOUNDARY = "----TestBoundary1234"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_multipart_body(
    fields: dict | None = None,
    file_content: bytes = b"Sample file content",
    file_field_name: str = "file",
    file_name: str = "assignment.pdf",
) -> bytes:
    """Build a raw multipart/form-data body with the given fields and file."""
    parts: list[bytes] = []

    # Regular form fields
    if fields:
        for name, value in fields.items():
            parts.append(
                f"--{BOUNDARY}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n'
                f"\r\n"
                f"{value}\r\n".encode()
            )

    # File field
    if file_name is not None:
        parts.append(
            f"--{BOUNDARY}\r\n"
            f'Content-Disposition: form-data; name="{file_field_name}"; filename="{file_name}"\r\n'
            f"Content-Type: application/octet-stream\r\n"
            f"\r\n".encode()
            + file_content
            + b"\r\n"
        )

    # Closing boundary
    parts.append(f"--{BOUNDARY}--\r\n".encode())

    return b"".join(parts)


def _make_apigw_event(
    body_bytes: bytes,
    is_base64: bool = True,
    content_type: str | None = None,
    claims: dict | None = None,
) -> dict:
    """Build an API Gateway proxy integration event."""
    if content_type is None:
        content_type = f"multipart/form-data; boundary={BOUNDARY}"

    encoded_body = base64.b64encode(body_bytes).decode() if is_base64 else body_bytes.decode()

    if claims is None:
        claims = {"sub": "user-123", "email": "student@university.edu"}

    return {
        "httpMethod": "POST",
        "headers": {
            "Content-Type": content_type,
        },
        "body": encoded_body,
        "isBase64Encoded": is_base64,
        "requestContext": {
            "authorizer": {
                "claims": claims,
            },
        },
    }


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _aws_env(monkeypatch):
    """Set environment variables expected by the Lambda function."""
    monkeypatch.setenv("RAW_BUCKET", RAW_BUCKET)
    monkeypatch.setenv("SUBMISSIONS_TABLE", SUBMISSIONS_TABLE)
    monkeypatch.setenv("AUDIT_TABLE", AUDIT_TABLE)
    monkeypatch.setenv("AUDIT_FUNCTION_NAME", AUDIT_FUNCTION_NAME)
    monkeypatch.setenv("MAX_FILE_SIZE", "1048576")  # 1 MiB for tests
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")


@pytest.fixture()
def aws_resources():
    """Create mocked S3 bucket and DynamoDB table, then yield."""
    with mock_aws():
        # S3
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket=RAW_BUCKET)

        # DynamoDB
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName=SUBMISSIONS_TABLE,
            KeySchema=[{"AttributeName": "submission_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "submission_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )

        # Lambda (create a minimal function so invoke doesn't fail)
        lam = boto3.client("lambda", region_name="us-east-1")
        lam.create_function(
            FunctionName=AUDIT_FUNCTION_NAME,
            Runtime="python3.11",
            Role="arn:aws:iam::123456789012:role/fake-role",
            Handler="index.handler",
            Code={"ZipFile": b"fake-zip"},
        )

        yield {
            "s3": s3,
            "dynamodb": dynamodb,
            "lambda": lam,
        }


def _import_handler():
    """Import (or re-import) the handler module so that it picks up mocked clients."""
    import importlib
    import lambda_function as mod

    importlib.reload(mod)
    return mod.lambda_handler


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestSuccessfulUpload:
    """Tests for the happy-path upload flow."""

    def test_successful_pdf_upload(self, aws_resources):
        """A valid PDF upload should return 200 with correct metadata."""
        handler = _import_handler()

        file_content = b"%PDF-1.4 fake pdf content for testing"
        body = _build_multipart_body(
            fields={
                "student_id": "stu-001",
                "course_id": "CS101",
                "section_id": "A",
            },
            file_content=file_content,
            file_name="homework.pdf",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)

        assert response["statusCode"] == 200

        resp_body = json.loads(response["body"])
        assert resp_body["message"] == "File uploaded successfully"
        assert resp_body["file_name"] == "homework.pdf"
        assert resp_body["file_size"] == len(file_content)
        assert resp_body["status"] == "uploaded"
        assert "submission_id" in resp_body
        assert "sha256_hash" in resp_body
        assert "upload_timestamp" in resp_body

        # Verify CORS headers
        assert response["headers"]["Access-Control-Allow-Origin"] == "*"

    def test_s3_object_created(self, aws_resources):
        """The uploaded file must exist in S3 at the expected key."""
        handler = _import_handler()

        file_content = b"print('hello')"
        body = _build_multipart_body(
            fields={
                "student_id": "stu-002",
                "course_id": "CS201",
                "section_id": "B",
            },
            file_content=file_content,
            file_name="script.py",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        resp_body = json.loads(response["body"])
        submission_id = resp_body["submission_id"]

        s3_key = f"submissions/stu-002/{submission_id}/script.py"
        obj = aws_resources["s3"].get_object(Bucket=RAW_BUCKET, Key=s3_key)
        assert obj["Body"].read() == file_content

    def test_dynamodb_item_written(self, aws_resources):
        """DynamoDB must contain a record with all required fields."""
        handler = _import_handler()

        file_content = b"<html></html>"
        body = _build_multipart_body(
            fields={
                "student_id": "stu-003",
                "course_id": "WEB100",
                "section_id": "C",
            },
            file_content=file_content,
            file_name="index.html",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        resp_body = json.loads(response["body"])
        submission_id = resp_body["submission_id"]

        table = aws_resources["dynamodb"].Table(SUBMISSIONS_TABLE)
        item = table.get_item(Key={"submission_id": submission_id})["Item"]

        assert item["student_id"] == "stu-003"
        assert item["course_id"] == "WEB100"
        assert item["section_id"] == "C"
        assert item["file_name"] == "index.html"
        assert item["file_type"] == ".html"
        assert item["status"] == "uploaded"
        assert item["file_size"] == len(file_content)
        assert "sha256_hash" in item
        assert "upload_timestamp" in item
        assert "file_path" in item


class TestSha256Hash:
    """Verify that the SHA-256 hash is computed correctly."""

    def test_sha256_matches_expected(self, aws_resources):
        handler = _import_handler()

        file_content = b"deterministic content for hashing"
        expected_hash = hashlib.sha256(file_content).hexdigest()

        body = _build_multipart_body(
            fields={
                "student_id": "stu-hash",
                "course_id": "HASH101",
                "section_id": "H",
            },
            file_content=file_content,
            file_name="hashme.txt",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        resp_body = json.loads(response["body"])

        assert resp_body["sha256_hash"] == expected_hash


class TestInvalidFileExtension:
    """Uploads with disallowed extensions must be rejected."""

    @pytest.mark.parametrize("filename", [
        "malware.exe",
        "archive.zip",
        "image.png",
        "spreadsheet.xlsx",
        "noextension",
    ])
    def test_invalid_extensions_rejected(self, aws_resources, filename):
        handler = _import_handler()

        body = _build_multipart_body(
            fields={
                "student_id": "stu-ext",
                "course_id": "CS101",
                "section_id": "A",
            },
            file_content=b"bad file",
            file_name=filename,
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        assert response["statusCode"] == 400
        assert "Invalid file type" in json.loads(response["body"])["error"] or \
               "error" in json.loads(response["body"])


class TestFileTooLarge:
    """Files exceeding MAX_FILE_SIZE must return 413."""

    def test_oversized_file_rejected(self, aws_resources):
        handler = _import_handler()

        # MAX_FILE_SIZE is set to 1 MiB in the fixture; create a file just over that
        file_content = b"x" * (1048576 + 1)

        body = _build_multipart_body(
            fields={
                "student_id": "stu-big",
                "course_id": "CS101",
                "section_id": "A",
            },
            file_content=file_content,
            file_name="bigfile.pdf",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        assert response["statusCode"] == 413
        assert "too large" in json.loads(response["body"])["error"].lower()


class TestMissingFields:
    """Requests missing required fields should return 400."""

    def test_missing_file(self, aws_resources):
        handler = _import_handler()

        # Build body without a file part -- only form fields
        parts = []
        for name, value in [("student_id", "stu"), ("course_id", "C"), ("section_id", "S")]:
            parts.append(
                f"--{BOUNDARY}\r\n"
                f'Content-Disposition: form-data; name="{name}"\r\n'
                f"\r\n"
                f"{value}\r\n".encode()
            )
        parts.append(f"--{BOUNDARY}--\r\n".encode())
        body_bytes = b"".join(parts)

        event = _make_apigw_event(body_bytes)
        response = handler(event, None)

        assert response["statusCode"] == 400
        assert "file" in json.loads(response["body"])["error"].lower()

    @pytest.mark.parametrize("missing_field", ["student_id", "course_id", "section_id"])
    def test_missing_metadata_field(self, aws_resources, missing_field):
        handler = _import_handler()

        fields = {
            "student_id": "stu-001",
            "course_id": "CS101",
            "section_id": "A",
        }
        del fields[missing_field]

        body = _build_multipart_body(
            fields=fields,
            file_content=b"content",
            file_name="file.txt",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        assert response["statusCode"] == 400
        assert missing_field in json.loads(response["body"])["error"]

    def test_empty_body_rejected(self, aws_resources):
        handler = _import_handler()

        event = _make_apigw_event(b"", is_base64=False)
        event["body"] = ""

        response = handler(event, None)
        assert response["statusCode"] == 400

    def test_wrong_content_type_rejected(self, aws_resources):
        handler = _import_handler()

        event = _make_apigw_event(b"{}", is_base64=False, content_type="application/json")

        response = handler(event, None)
        assert response["statusCode"] == 400
        assert "multipart/form-data" in json.loads(response["body"])["error"]


class TestOptionsRequest:
    """CORS preflight requests should be handled."""

    def test_options_returns_200(self, aws_resources):
        handler = _import_handler()

        event = {
            "httpMethod": "OPTIONS",
            "headers": {},
            "body": None,
            "isBase64Encoded": False,
            "requestContext": {"authorizer": {"claims": {}}},
        }

        response = handler(event, None)
        assert response["statusCode"] == 200
        assert response["headers"]["Access-Control-Allow-Origin"] == "*"
        assert response["headers"]["Access-Control-Allow-Methods"] == "POST,OPTIONS"


class TestAllAllowedExtensions:
    """Every extension in the allow-list should be accepted."""

    @pytest.mark.parametrize("ext", [
        ".pdf", ".docx", ".txt", ".py", ".java", ".cpp",
        ".c", ".js", ".html", ".css", ".ipynb", ".tex",
    ])
    def test_allowed_extension_accepted(self, aws_resources, ext):
        handler = _import_handler()

        body = _build_multipart_body(
            fields={
                "student_id": "stu-ext",
                "course_id": "CS101",
                "section_id": "A",
            },
            file_content=b"valid content",
            file_name=f"assignment{ext}",
        )
        event = _make_apigw_event(body)

        response = handler(event, None)
        assert response["statusCode"] == 200, (
            f"Extension {ext} should be allowed but got {response['statusCode']}"
        )
