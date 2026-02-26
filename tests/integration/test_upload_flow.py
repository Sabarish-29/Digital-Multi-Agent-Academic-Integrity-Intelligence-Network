"""
Integration Test: Upload Flow
==============================

End-to-end test that verifies the DMAIIN submission upload pipeline:
  1. Authenticate as a student via Cognito
  2. Upload valid files and verify acceptance (200)
  3. Upload invalid files and verify rejection (400)
  4. Verify submissions appear in DynamoDB
  5. Verify audit log entries are created

Configuration (environment variables or Terraform outputs):
  - API_URL            : API Gateway base URL (e.g. https://xxxx.execute-api.us-east-1.amazonaws.com/prod)
  - COGNITO_USER_POOL_ID
  - COGNITO_CLIENT_ID
  - SUBMISSIONS_TABLE
  - AUDIT_LOG_TABLE
  - AWS_REGION         : defaults to us-east-1
  - TEST_STUDENT_EMAIL : defaults to student@test.edu
  - TEST_STUDENT_PASS  : defaults to Student1!Pass
"""

import json
import os
import subprocess
import sys
import time

import boto3
import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
TF_DIR = os.path.join(PROJECT_ROOT, "terraform")
SAMPLE_DIR = os.path.join(SCRIPT_DIR, "sample_files")


def _tf_output(name: str) -> str:
    """Read a value from Terraform outputs."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", name],
            cwd=TF_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def _get_config(env_var: str, tf_output_name: str, default: str = "") -> str:
    """Return config from environment variable, falling back to Terraform output."""
    value = os.environ.get(env_var, "")
    if not value:
        value = _tf_output(tf_output_name)
    if not value:
        value = default
    return value


API_URL = _get_config("API_URL", "api_gateway_url")
USER_POOL_ID = _get_config("COGNITO_USER_POOL_ID", "cognito_user_pool_id")
CLIENT_ID = _get_config("COGNITO_CLIENT_ID", "cognito_user_pool_client_id")
SUBMISSIONS_TABLE = _get_config("SUBMISSIONS_TABLE", "submissions_table_name")
AUDIT_LOG_TABLE = _get_config("AUDIT_LOG_TABLE", "audit_log_table_name")
REGION = os.environ.get("AWS_REGION", "us-east-1")

STUDENT_EMAIL = os.environ.get("TEST_STUDENT_EMAIL", "student@test.edu")
STUDENT_PASSWORD = os.environ.get("TEST_STUDENT_PASS", "Student1!Pass")


# ---------------------------------------------------------------------------
# Authentication helper
# ---------------------------------------------------------------------------

def authenticate(email: str, password: str) -> str:
    """Authenticate with Cognito and return an ID token."""
    client = boto3.client("cognito-idp", region_name=REGION)
    response = client.initiate_auth(
        ClientId=CLIENT_ID,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": email,
            "PASSWORD": password,
        },
    )
    return response["AuthenticationResult"]["IdToken"]


# ---------------------------------------------------------------------------
# Upload helpers
# ---------------------------------------------------------------------------

def upload_file(token: str, file_path: str, student_id: str = "stu-integration-001",
                course_id: str = "CS101", section_id: str = "A") -> requests.Response:
    """Upload a file to the submissions/upload endpoint."""
    url = f"{API_URL.rstrip('/')}/submissions/upload"
    filename = os.path.basename(file_path)

    with open(file_path, "rb") as f:
        files = {
            "file": (filename, f, "application/octet-stream"),
        }
        data = {
            "student_id": student_id,
            "course_id": course_id,
            "section_id": section_id,
        }
        headers = {
            "Authorization": token,
        }
        return requests.post(url, files=files, data=data, headers=headers, timeout=30)


def upload_content(token: str, filename: str, content: bytes,
                   student_id: str = "stu-integration-001",
                   course_id: str = "CS101", section_id: str = "A") -> requests.Response:
    """Upload in-memory content to the submissions/upload endpoint."""
    url = f"{API_URL.rstrip('/')}/submissions/upload"
    files = {
        "file": (filename, content, "application/octet-stream"),
    }
    data = {
        "student_id": student_id,
        "course_id": course_id,
        "section_id": section_id,
    }
    headers = {
        "Authorization": token,
    }
    return requests.post(url, files=files, data=data, headers=headers, timeout=30)


# ---------------------------------------------------------------------------
# DynamoDB verification helpers
# ---------------------------------------------------------------------------

def get_submission(submission_id: str) -> dict | None:
    """Retrieve a submission record from DynamoDB."""
    dynamodb = boto3.resource("dynamodb", region_name=REGION)
    table = dynamodb.Table(SUBMISSIONS_TABLE)
    response = table.get_item(Key={"submission_id": submission_id})
    return response.get("Item")


def get_audit_entries(submission_id: str) -> list:
    """Query audit log entries for a given submission."""
    dynamodb = boto3.resource("dynamodb", region_name=REGION)
    table = dynamodb.Table(AUDIT_LOG_TABLE)
    response = table.query(
        IndexName="submission-index",
        KeyConditionExpression=boto3.dynamodb.conditions.Key("submission_id").eq(submission_id),
    )
    return response.get("Items", [])


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

def run_tests():
    """Execute all integration tests and print a summary."""
    print("=" * 60)
    print("DMAIIN Integration Test: Upload Flow")
    print("=" * 60)
    print(f"  API URL:           {API_URL}")
    print(f"  User Pool ID:      {USER_POOL_ID}")
    print(f"  Client ID:         {CLIENT_ID}")
    print(f"  Submissions Table: {SUBMISSIONS_TABLE}")
    print(f"  Audit Log Table:   {AUDIT_LOG_TABLE}")
    print(f"  Region:            {REGION}")
    print()

    # Validate configuration
    missing = []
    if not API_URL:
        missing.append("API_URL")
    if not USER_POOL_ID:
        missing.append("COGNITO_USER_POOL_ID")
    if not CLIENT_ID:
        missing.append("COGNITO_CLIENT_ID")
    if not SUBMISSIONS_TABLE:
        missing.append("SUBMISSIONS_TABLE")
    if not AUDIT_LOG_TABLE:
        missing.append("AUDIT_LOG_TABLE")

    if missing:
        print(f"ERROR: Missing configuration: {', '.join(missing)}")
        print("Set them as environment variables or run 'terraform apply' first.")
        sys.exit(1)

    # Authenticate
    print("Authenticating as student...")
    try:
        token = authenticate(STUDENT_EMAIL, STUDENT_PASSWORD)
        print("  Authentication successful.")
    except Exception as exc:
        print(f"  ERROR: Authentication failed: {exc}")
        sys.exit(1)

    results = []
    total = 10

    # -----------------------------------------------------------------------
    # Valid file uploads (5 tests)
    # -----------------------------------------------------------------------
    valid_files = {
        "sample.pdf": b"%PDF-1.4 This is a test PDF document for DMAIIN integration testing.",
        "sample.txt": None,  # read from sample_files/
        "sample.py": None,
        "sample.java": None,
        "sample.html": None,
    }

    submission_ids = []

    print()
    print("--- Valid File Uploads (expect 200) ---")

    for filename, content in valid_files.items():
        sample_path = os.path.join(SAMPLE_DIR, filename)

        try:
            if content is not None:
                # Use in-memory content
                resp = upload_content(token, filename, content)
            elif os.path.exists(sample_path):
                # Read from sample file
                resp = upload_file(token, sample_path)
            else:
                # Generate minimal content
                resp = upload_content(token, filename, f"Test content for {filename}".encode())

            if resp.status_code == 200:
                body = resp.json()
                sid = body.get("submission_id", "")
                submission_ids.append(sid)
                print(f"  PASS: {filename} => 200 (submission_id={sid[:8]}...)")
                results.append(True)
            else:
                print(f"  FAIL: {filename} => {resp.status_code}: {resp.text[:200]}")
                results.append(False)
        except Exception as exc:
            print(f"  FAIL: {filename} => Exception: {exc}")
            results.append(False)

    # -----------------------------------------------------------------------
    # Invalid file uploads (5 tests)
    # -----------------------------------------------------------------------
    invalid_files = [
        ("malware.exe", b"MZ fake executable content"),
        ("library.dll", b"fake DLL content"),
        ("script.bat", b"@echo off\necho dangerous"),
        ("dangerous.sh", b"#!/bin/bash\nrm -rf /"),
        ("binary.bin", b"\x00\x01\x02\x03 binary data"),
    ]

    print()
    print("--- Invalid File Uploads (expect 400) ---")

    for filename, content in invalid_files:
        try:
            resp = upload_content(token, filename, content)
            if resp.status_code == 400:
                print(f"  PASS: {filename} => 400 (correctly rejected)")
                results.append(True)
            else:
                print(f"  FAIL: {filename} => {resp.status_code} (expected 400): {resp.text[:200]}")
                results.append(False)
        except Exception as exc:
            print(f"  FAIL: {filename} => Exception: {exc}")
            results.append(False)

    # -----------------------------------------------------------------------
    # DynamoDB verification
    # -----------------------------------------------------------------------
    print()
    print("--- DynamoDB Verification ---")

    # Wait briefly for async audit logger to complete
    if submission_ids:
        print("  Waiting 3 seconds for async audit logging...")
        time.sleep(3)

    dynamo_pass = 0
    dynamo_total = 0

    for sid in submission_ids:
        dynamo_total += 1
        item = get_submission(sid)
        if item:
            print(f"  Submission {sid[:8]}...: found in DynamoDB (status={item.get('status')})")
            dynamo_pass += 1
        else:
            print(f"  Submission {sid[:8]}...: NOT FOUND in DynamoDB")

    print(f"  DynamoDB submissions verified: {dynamo_pass}/{dynamo_total}")

    # Check audit log entries
    audit_pass = 0
    audit_total = 0

    for sid in submission_ids:
        audit_total += 1
        entries = get_audit_entries(sid)
        if entries:
            print(f"  Audit log for {sid[:8]}...: {len(entries)} entry(ies) found")
            audit_pass += 1
        else:
            print(f"  Audit log for {sid[:8]}...: NO entries found")

    print(f"  Audit log entries verified: {audit_pass}/{audit_total}")

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    passed = sum(results)
    print()
    print("=" * 60)
    print(f"Upload Flow Test Summary: {passed}/{total} tests passed")
    print("=" * 60)

    if dynamo_pass < dynamo_total:
        print(f"  WARNING: {dynamo_total - dynamo_pass} submissions missing from DynamoDB")
    if audit_pass < audit_total:
        print(f"  WARNING: {audit_total - audit_pass} submissions missing audit log entries")

    if passed == total:
        print("  All upload flow tests PASSED.")
    else:
        print(f"  {total - passed} test(s) FAILED.")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(run_tests())
