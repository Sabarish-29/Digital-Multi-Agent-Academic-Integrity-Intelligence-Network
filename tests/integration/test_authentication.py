"""
Integration Test: Authentication & Authorization
==================================================

End-to-end test that verifies the DMAIIN authentication and authorization flow:
  1. Sign in with valid credentials (expect success)
  2. Sign in with invalid credentials (expect failure)
  3. Access API without token (expect 401)
  4. Access API with valid token (expect 200)
  5. Student cannot access another student's submission (expect 403)

Configuration (environment variables or Terraform outputs):
  - API_URL
  - COGNITO_USER_POOL_ID
  - COGNITO_CLIENT_ID
  - SUBMISSIONS_TABLE
  - AWS_REGION          : defaults to us-east-1
  - TEST_STUDENT_EMAIL  : defaults to student@test.edu
  - TEST_STUDENT_PASS   : defaults to Student1!Pass
  - TEST_FACULTY_EMAIL  : defaults to faculty@test.edu
  - TEST_FACULTY_PASS   : defaults to Faculty1!Pass
"""

import json
import os
import subprocess
import sys
import uuid

import boto3
import requests
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
TF_DIR = os.path.join(PROJECT_ROOT, "terraform")


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
REGION = os.environ.get("AWS_REGION", "us-east-1")

STUDENT_EMAIL = os.environ.get("TEST_STUDENT_EMAIL", "student@test.edu")
STUDENT_PASSWORD = os.environ.get("TEST_STUDENT_PASS", "Student1!Pass")
FACULTY_EMAIL = os.environ.get("TEST_FACULTY_EMAIL", "faculty@test.edu")
FACULTY_PASSWORD = os.environ.get("TEST_FACULTY_PASS", "Faculty1!Pass")


# ---------------------------------------------------------------------------
# Authentication helpers
# ---------------------------------------------------------------------------

def authenticate(email: str, password: str) -> dict:
    """
    Authenticate with Cognito and return the full AuthenticationResult.
    Returns a dict with IdToken, AccessToken, RefreshToken, etc.
    Raises an exception on failure.
    """
    client = boto3.client("cognito-idp", region_name=REGION)
    response = client.initiate_auth(
        ClientId=CLIENT_ID,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": email,
            "PASSWORD": password,
        },
    )
    return response["AuthenticationResult"]


def get_submission_metadata(token: str, submission_id: str) -> requests.Response:
    """GET /submissions/{id} with the provided auth token."""
    url = f"{API_URL.rstrip('/')}/submissions/{submission_id}"
    headers = {"Authorization": token}
    return requests.get(url, headers=headers, timeout=30)


def get_submission_metadata_no_auth(submission_id: str) -> requests.Response:
    """GET /submissions/{id} without any auth token."""
    url = f"{API_URL.rstrip('/')}/submissions/{submission_id}"
    return requests.get(url, timeout=30)


# ---------------------------------------------------------------------------
# Seed data helper
# ---------------------------------------------------------------------------

def seed_submission_for_other_student() -> str:
    """
    Insert a fake submission record into DynamoDB owned by a different student.
    Returns the submission_id.
    """
    dynamodb = boto3.resource("dynamodb", region_name=REGION)
    table = dynamodb.Table(SUBMISSIONS_TABLE)

    submission_id = str(uuid.uuid4())
    table.put_item(Item={
        "submission_id": submission_id,
        "student_id": "other-student-sub-9999",
        "course_id": "CS999",
        "section_id": "Z",
        "file_path": "s3://fake-bucket/fake-key",
        "file_name": "other_student_file.txt",
        "file_size": 42,
        "file_type": ".txt",
        "sha256_hash": "abcdef1234567890",
        "upload_timestamp": "2025-01-01T00:00:00+00:00",
        "status": "uploaded",
        "user_id": "other-student-sub-9999",
        "email": "other@test.edu",
    })

    return submission_id


def cleanup_submission(submission_id: str) -> None:
    """Delete a seeded submission from DynamoDB."""
    try:
        dynamodb = boto3.resource("dynamodb", region_name=REGION)
        table = dynamodb.Table(SUBMISSIONS_TABLE)
        table.delete_item(Key={"submission_id": submission_id})
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

def run_tests():
    """Execute all authentication integration tests and print a summary."""
    print("=" * 60)
    print("DMAIIN Integration Test: Authentication & Authorization")
    print("=" * 60)
    print(f"  API URL:      {API_URL}")
    print(f"  User Pool ID: {USER_POOL_ID}")
    print(f"  Client ID:    {CLIENT_ID}")
    print(f"  Region:       {REGION}")
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

    if missing:
        print(f"ERROR: Missing configuration: {', '.join(missing)}")
        print("Set them as environment variables or run 'terraform apply' first.")
        sys.exit(1)

    results = []
    total = 5
    seeded_submission_id = None

    try:
        # -------------------------------------------------------------------
        # Test 1: Sign in with valid credentials
        # -------------------------------------------------------------------
        print("Test 1: Sign in with valid credentials")
        try:
            auth_result = authenticate(STUDENT_EMAIL, STUDENT_PASSWORD)
            student_token = auth_result["IdToken"]
            if student_token:
                print(f"  PASS: Successfully authenticated as {STUDENT_EMAIL}")
                results.append(True)
            else:
                print("  FAIL: Authentication returned empty token")
                results.append(False)
                student_token = ""
        except Exception as exc:
            print(f"  FAIL: Authentication failed with exception: {exc}")
            results.append(False)
            student_token = ""

        # -------------------------------------------------------------------
        # Test 2: Sign in with invalid credentials
        # -------------------------------------------------------------------
        print()
        print("Test 2: Sign in with invalid credentials")
        try:
            authenticate(STUDENT_EMAIL, "WrongPassword123!")
            print("  FAIL: Authentication should have failed but succeeded")
            results.append(False)
        except ClientError as exc:
            error_code = exc.response.get("Error", {}).get("Code", "")
            if error_code in ("NotAuthorizedException", "UserNotFoundException"):
                print(f"  PASS: Correctly rejected invalid credentials ({error_code})")
                results.append(True)
            else:
                print(f"  FAIL: Unexpected error code: {error_code}")
                results.append(False)
        except Exception as exc:
            print(f"  FAIL: Unexpected exception: {exc}")
            results.append(False)

        # -------------------------------------------------------------------
        # Test 3: Access API without token returns 401
        # -------------------------------------------------------------------
        print()
        print("Test 3: Access API without token (expect 401)")
        try:
            # Use a fake submission ID since we just want to test auth
            resp = get_submission_metadata_no_auth("nonexistent-id-12345")
            if resp.status_code == 401:
                print(f"  PASS: Received 401 Unauthorized as expected")
                results.append(True)
            elif resp.status_code == 403:
                # API Gateway may return 403 instead of 401 for missing auth
                print(f"  PASS: Received 403 Forbidden (API Gateway auth rejection)")
                results.append(True)
            else:
                print(f"  FAIL: Expected 401 or 403, got {resp.status_code}: {resp.text[:200]}")
                results.append(False)
        except Exception as exc:
            print(f"  FAIL: Exception: {exc}")
            results.append(False)

        # -------------------------------------------------------------------
        # Test 4: Access API with valid token returns 200 (or 404 for non-existent)
        # -------------------------------------------------------------------
        print()
        print("Test 4: Access API with valid token (expect 200 or 404)")
        try:
            if not student_token:
                print("  SKIP: No valid token available (Test 1 failed)")
                results.append(False)
            else:
                # Request a non-existent submission -- should get 404 (not 401/403)
                resp = get_submission_metadata(student_token, "nonexistent-id-12345")
                if resp.status_code == 404:
                    print(f"  PASS: Received 404 (token accepted, submission not found)")
                    results.append(True)
                elif resp.status_code == 200:
                    print(f"  PASS: Received 200 (token accepted)")
                    results.append(True)
                elif resp.status_code in (401, 403):
                    print(f"  FAIL: Received {resp.status_code} despite valid token: {resp.text[:200]}")
                    results.append(False)
                else:
                    print(f"  FAIL: Unexpected status {resp.status_code}: {resp.text[:200]}")
                    results.append(False)
        except Exception as exc:
            print(f"  FAIL: Exception: {exc}")
            results.append(False)

        # -------------------------------------------------------------------
        # Test 5: Student cannot access another student's submission (expect 403)
        # -------------------------------------------------------------------
        print()
        print("Test 5: Student cannot access another student's submission (expect 403)")
        try:
            if not student_token:
                print("  SKIP: No valid token available (Test 1 failed)")
                results.append(False)
            else:
                # Seed a submission owned by a different student
                seeded_submission_id = seed_submission_for_other_student()
                print(f"  Seeded submission: {seeded_submission_id[:8]}... (owned by other-student)")

                resp = get_submission_metadata(student_token, seeded_submission_id)
                if resp.status_code == 403:
                    print(f"  PASS: Received 403 Forbidden (correctly denied cross-student access)")
                    results.append(True)
                elif resp.status_code == 200:
                    print(f"  FAIL: Received 200 (student was incorrectly allowed to access another's submission)")
                    results.append(False)
                else:
                    print(f"  INFO: Received {resp.status_code}: {resp.text[:200]}")
                    # 404 could mean the authorization check happens differently
                    if resp.status_code == 404:
                        print("  FAIL: 404 suggests the record was not found (seeding issue)")
                    results.append(False)
        except Exception as exc:
            print(f"  FAIL: Exception: {exc}")
            results.append(False)

    finally:
        # Cleanup seeded data
        if seeded_submission_id:
            cleanup_submission(seeded_submission_id)
            print(f"\n  Cleaned up seeded submission: {seeded_submission_id[:8]}...")

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    passed = sum(results)
    print()
    print("=" * 60)
    print(f"Authentication Test Summary: {passed}/{total} tests passed")
    print("=" * 60)

    if passed == total:
        print("  All authentication tests PASSED.")
    else:
        print(f"  {total - passed} test(s) FAILED.")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(run_tests())
