#!/bin/bash
set -euo pipefail

# =============================================================================
# DMAIIN - Cleanup / Destroy All Resources
# =============================================================================
#
# Empties all S3 buckets (required before Terraform can destroy them) and then
# runs terraform destroy to tear down all AWS infrastructure.
#
# Usage:
#   ./scripts/cleanup.sh
#
# Make executable:
#   chmod +x scripts/cleanup.sh
#
# WARNING: This script is DESTRUCTIVE. It will permanently delete all data
#          and infrastructure created by the DMAIIN Phase 1 deployment.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="${PROJECT_ROOT}/terraform"

echo "=========================================="
echo "DMAIIN Cleanup - Destroy All Resources"
echo "=========================================="
echo ""
echo "WARNING: This will permanently delete ALL data and infrastructure."
echo ""

# Prompt for confirmation
read -r -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
if [ "$confirmation" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1: Empty S3 buckets
# ---------------------------------------------------------------------------
echo "[1/2] Emptying S3 buckets..."
echo "-------------------------------------------"

cd "$TF_DIR"

# Collect bucket names from Terraform outputs (ignore errors if not yet applied)
BUCKETS=()

for output_name in raw_bucket_name processed_bucket_name reports_bucket_name frontend_bucket_name; do
    bucket_name=$(terraform output -raw "$output_name" 2>/dev/null || true)
    if [ -n "$bucket_name" ]; then
        BUCKETS+=("$bucket_name")
    fi
done

if [ ${#BUCKETS[@]} -eq 0 ]; then
    echo "  No buckets found in Terraform outputs (infrastructure may not be deployed)."
    echo "  Skipping bucket cleanup."
else
    for bucket in "${BUCKETS[@]}"; do
        echo "  Emptying bucket: ${bucket}"

        # Remove all object versions (required for versioned buckets)
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output json 2>/dev/null | \
        python3 -c "
import sys, json
try:
    objects = json.load(sys.stdin)
    if objects:
        for obj in objects:
            print(f\"  Deleting: {obj['Key']} (version: {obj['VersionId']})\")
except:
    pass
" 2>/dev/null || true

        # Delete all objects including versions and delete markers
        aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true

        # Delete all object versions
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --output json 2>/dev/null | \
        python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
bucket = '${bucket}'
for version_list in ['Versions', 'DeleteMarkers']:
    for obj in data.get(version_list, []) or []:
        key = obj['Key']
        vid = obj['VersionId']
        subprocess.run([
            'aws', 's3api', 'delete-object',
            '--bucket', bucket,
            '--key', key,
            '--version-id', vid
        ], capture_output=True)
        print(f'  Purged: {key} ({vid})')
" 2>/dev/null || true

        echo "  Bucket emptied: ${bucket}"
    done
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Terraform destroy
# ---------------------------------------------------------------------------
echo "[2/2] Destroying infrastructure with Terraform..."
echo "-------------------------------------------"

cd "$TF_DIR"

terraform init -input=false 2>/dev/null
terraform destroy -auto-approve

echo ""
echo "=========================================="
echo "Cleanup complete."
echo "All DMAIIN Phase 1 resources have been destroyed."
echo "=========================================="
