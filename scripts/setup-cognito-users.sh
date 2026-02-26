#!/bin/bash
set -euo pipefail

# =============================================================================
# DMAIIN - Cognito Test User Setup Script
# =============================================================================
#
# Creates test users in the Cognito User Pool for development and integration
# testing. Each user is assigned to the appropriate group (Students, Faculty,
# or Admin).
#
# Usage:
#   ./scripts/setup-cognito-users.sh
#
# Make executable:
#   chmod +x scripts/setup-cognito-users.sh
#
# Requires:
#   - AWS CLI configured with appropriate credentials
#   - USER_POOL_ID environment variable (or reads from Terraform output)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Resolve User Pool ID from environment or Terraform output
USER_POOL_ID="${USER_POOL_ID:-}"
if [ -z "$USER_POOL_ID" ]; then
    echo "USER_POOL_ID not set. Attempting to read from Terraform outputs..."
    USER_POOL_ID=$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw cognito_user_pool_id 2>/dev/null || true)
fi

if [ -z "$USER_POOL_ID" ]; then
    echo "ERROR: Could not determine USER_POOL_ID."
    echo "Either set the USER_POOL_ID environment variable or run 'terraform apply' first."
    exit 1
fi

REGION="${AWS_REGION:-us-east-1}"

echo "=========================================="
echo "DMAIIN Cognito Test User Setup"
echo "=========================================="
echo "User Pool ID: ${USER_POOL_ID}"
echo "Region:       ${REGION}"
echo ""

# ---------------------------------------------------------------------------
# Helper function to create a user, set permanent password, and add to group
# ---------------------------------------------------------------------------
create_user() {
    local username="$1"
    local name="$2"
    local password="$3"
    local group="$4"

    echo "Creating user: ${username}"
    echo "  Name:  ${name}"
    echo "  Group: ${group}"

    # Create the user with a temporary password
    aws cognito-idp admin-create-user \
        --user-pool-id "$USER_POOL_ID" \
        --username "$username" \
        --user-attributes \
            Name=email,Value="$username" \
            Name=name,Value="$name" \
            Name=email_verified,Value=true \
        --temporary-password "TempPass1!" \
        --message-action SUPPRESS \
        --region "$REGION" \
        2>/dev/null || echo "  (User may already exist, continuing...)"

    # Set the permanent password (bypasses forced password change)
    aws cognito-idp admin-set-user-password \
        --user-pool-id "$USER_POOL_ID" \
        --username "$username" \
        --password "$password" \
        --permanent \
        --region "$REGION"

    # Add the user to the specified group
    aws cognito-idp admin-add-user-to-group \
        --user-pool-id "$USER_POOL_ID" \
        --username "$username" \
        --group-name "$group" \
        --region "$REGION"

    echo "  Done."
    echo ""
}

# ---------------------------------------------------------------------------
# Create test users
# ---------------------------------------------------------------------------

echo "--- Student User ---"
create_user \
    "student@test.edu" \
    "Test Student" \
    "Student1!Pass" \
    "Students"

echo "--- Faculty User ---"
create_user \
    "faculty@test.edu" \
    "Test Faculty" \
    "Faculty1!Pass" \
    "Faculty"

echo "--- Admin User ---"
create_user \
    "admin@test.edu" \
    "Test Admin" \
    "Admin1!Pass" \
    "Admin"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=========================================="
echo "Test users created successfully."
echo "=========================================="
echo ""
echo "Credentials:"
echo "  Student: student@test.edu / Student1!Pass  (Group: Students)"
echo "  Faculty: faculty@test.edu / Faculty1!Pass  (Group: Faculty)"
echo "  Admin:   admin@test.edu   / Admin1!Pass    (Group: Admin)"
echo ""
echo "WARNING: These are test credentials. Do NOT use in production."
echo ""
