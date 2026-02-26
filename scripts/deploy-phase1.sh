#!/bin/bash
set -euo pipefail

# =============================================================================
# DMAIIN Phase 1 Deployment Script
# =============================================================================
#
# Usage:
#   ./scripts/deploy-phase1.sh [plan|apply|destroy|test]
#
# Make executable:
#   chmod +x scripts/deploy-phase1.sh
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Terraform >= 1.5.0
#   - Node.js >= 20 and npm
#   - Python 3.11+ and pip
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ACTION="${1:-plan}"

echo "=========================================="
echo "DMAIIN Phase 1 Deployment"
echo "Action: $ACTION"
echo "Time:   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "=========================================="

# =============================================================================
# Step 1: Validate prerequisites
# =============================================================================
check_prerequisites() {
    echo ""
    echo "[1/5] Checking prerequisites..."
    echo "-------------------------------------------"

    local missing=0

    if ! command -v aws &>/dev/null; then
        echo "  ERROR: AWS CLI not found. Install from https://aws.amazon.com/cli/"
        missing=1
    else
        echo "  AWS CLI:   $(aws --version 2>&1 | head -1)"
    fi

    if ! command -v terraform &>/dev/null; then
        echo "  ERROR: Terraform not found. Install from https://www.terraform.io/downloads"
        missing=1
    else
        echo "  Terraform: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"
    fi

    if ! command -v node &>/dev/null; then
        echo "  ERROR: Node.js not found. Install from https://nodejs.org/"
        missing=1
    else
        echo "  Node.js:   $(node --version)"
    fi

    if ! command -v npm &>/dev/null; then
        echo "  ERROR: npm not found. Install Node.js from https://nodejs.org/"
        missing=1
    else
        echo "  npm:       $(npm --version)"
    fi

    if ! command -v python3 &>/dev/null; then
        echo "  ERROR: Python 3 not found. Install from https://www.python.org/"
        missing=1
    else
        echo "  Python:    $(python3 --version)"
    fi

    if ! command -v pip &>/dev/null && ! command -v pip3 &>/dev/null; then
        echo "  ERROR: pip not found. Install with: python3 -m ensurepip"
        missing=1
    else
        echo "  pip:       $(pip3 --version 2>/dev/null || pip --version)"
    fi

    if [ "$missing" -ne 0 ]; then
        echo ""
        echo "ERROR: Missing prerequisites. Please install the tools listed above."
        exit 1
    fi

    # Verify AWS credentials are configured
    if ! aws sts get-caller-identity &>/dev/null; then
        echo ""
        echo "  ERROR: AWS credentials not configured or invalid."
        echo "  Run 'aws configure' or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
        exit 1
    fi

    echo "  AWS Account: $(aws sts get-caller-identity --query 'Account' --output text)"
    echo "  All prerequisites satisfied."
}

# =============================================================================
# Step 2: Package Lambda functions
# =============================================================================
package_lambdas() {
    echo ""
    echo "[2/5] Packaging Lambda functions..."
    echo "-------------------------------------------"

    local lambda_base_dir="${PROJECT_ROOT}/lambda"

    for lambda_dir in "${lambda_base_dir}"/*/; do
        local lambda_name
        lambda_name="$(basename "$lambda_dir")"

        echo "  Packaging: ${lambda_name}"

        # Skip if directory does not contain a lambda_function.py
        if [ ! -f "${lambda_dir}/lambda_function.py" ]; then
            echo "    Skipping (no lambda_function.py found)"
            continue
        fi

        # Install dependencies into a temporary package directory
        if [ -f "${lambda_dir}/requirements.txt" ]; then
            echo "    Installing dependencies..."
            pip3 install \
                --quiet \
                --requirement "${lambda_dir}/requirements.txt" \
                --target "${lambda_dir}/package/" \
                --upgrade
        else
            mkdir -p "${lambda_dir}/package/"
        fi

        # Copy the Lambda source into the package directory
        cp "${lambda_dir}/lambda_function.py" "${lambda_dir}/package/"

        # Create the deployment zip
        echo "    Creating package.zip..."
        (
            cd "${lambda_dir}/package"
            zip -r -q "${lambda_dir}/package.zip" .
        )

        # Clean up the temporary package directory
        rm -rf "${lambda_dir}/package/"

        echo "    Done: ${lambda_dir}/package.zip"
    done

    echo "  All Lambda functions packaged."
}

# =============================================================================
# Step 3: Terraform init + plan/apply/destroy
# =============================================================================
run_terraform() {
    echo ""
    echo "[3/5] Running Terraform ($ACTION)..."
    echo "-------------------------------------------"

    local tf_dir="${PROJECT_ROOT}/terraform"
    cd "$tf_dir"

    echo "  Initializing Terraform..."
    terraform init -input=false

    case "$ACTION" in
        plan)
            echo "  Creating execution plan..."
            terraform plan -out=tfplan
            echo ""
            echo "  Plan saved to terraform/tfplan"
            echo "  To apply, run: ./scripts/deploy-phase1.sh apply"
            ;;
        apply)
            echo "  Creating execution plan..."
            terraform plan -out=tfplan
            echo ""
            echo "  Applying infrastructure changes..."
            terraform apply tfplan
            echo ""
            echo "  Infrastructure deployed successfully."
            echo ""
            echo "  Outputs:"
            terraform output
            ;;
        destroy)
            echo "  WARNING: This will destroy ALL infrastructure."
            echo ""
            terraform destroy
            ;;
        test)
            # No terraform action needed for test
            echo "  Skipping Terraform (test mode)."
            ;;
        *)
            echo "  ERROR: Unknown action '$ACTION'. Use: plan, apply, destroy, or test"
            exit 1
            ;;
    esac

    cd "$PROJECT_ROOT"
}

# =============================================================================
# Step 4: Build and deploy frontend
# =============================================================================
deploy_frontend() {
    echo ""
    echo "[4/5] Building and deploying frontend..."
    echo "-------------------------------------------"

    local frontend_dir="${PROJECT_ROOT}/frontend"
    cd "$frontend_dir"

    echo "  Installing npm dependencies..."
    npm install --silent

    # Retrieve Terraform outputs needed for the frontend build
    local tf_dir="${PROJECT_ROOT}/terraform"
    export REACT_APP_API_URL
    REACT_APP_API_URL=$(cd "$tf_dir" && terraform output -raw api_gateway_url)
    export REACT_APP_COGNITO_USER_POOL_ID
    REACT_APP_COGNITO_USER_POOL_ID=$(cd "$tf_dir" && terraform output -raw cognito_user_pool_id)
    export REACT_APP_COGNITO_CLIENT_ID
    REACT_APP_COGNITO_CLIENT_ID=$(cd "$tf_dir" && terraform output -raw cognito_user_pool_client_id)
    export REACT_APP_AWS_REGION
    REACT_APP_AWS_REGION=$(cd "$tf_dir" && terraform output -raw aws_region)

    echo "  Building production bundle..."
    npm run build

    # Retrieve the frontend bucket name from Terraform outputs
    local frontend_bucket
    frontend_bucket=$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw frontend_bucket_name)

    if [ -z "$frontend_bucket" ]; then
        echo "  ERROR: Could not retrieve frontend_bucket_name from Terraform outputs."
        echo "  Make sure 'terraform apply' has been run successfully."
        exit 1
    fi

    echo "  Deploying to S3 bucket: ${frontend_bucket}"
    aws s3 sync build/ "s3://${frontend_bucket}/" --delete

    local frontend_url
    frontend_url=$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw frontend_url 2>/dev/null || echo "")

    echo ""
    echo "  Frontend deployed successfully."
    if [ -n "$frontend_url" ]; then
        echo "  URL: ${frontend_url}"
    fi

    cd "$PROJECT_ROOT"
}

# =============================================================================
# Step 5: Run integration tests
# =============================================================================
run_tests() {
    echo ""
    echo "[5/5] Running integration tests..."
    echo "-------------------------------------------"

    local test_dir="${PROJECT_ROOT}/tests/integration"

    echo "  Installing test dependencies..."
    pip3 install --quiet boto3 requests

    echo "  Running upload flow tests..."
    python3 "${test_dir}/test_upload_flow.py"

    echo ""
    echo "  Running authentication tests..."
    python3 "${test_dir}/test_authentication.py"

    echo ""
    echo "  Integration tests complete."
}

# =============================================================================
# Main execution
# =============================================================================
main() {
    check_prerequisites
    package_lambdas
    run_terraform

    if [ "$ACTION" = "apply" ]; then
        deploy_frontend
        echo ""
        echo "=========================================="
        echo "Deployment complete!"
        echo "=========================================="
        echo ""
        echo "Next steps:"
        echo "  1. Create test users: ./scripts/setup-cognito-users.sh"
        echo "  2. Run integration tests: ./scripts/deploy-phase1.sh test"
        echo ""
    fi

    if [ "$ACTION" = "test" ]; then
        run_tests
    fi

    if [ "$ACTION" = "plan" ]; then
        echo ""
        echo "=========================================="
        echo "Plan complete. Review the output above."
        echo "To apply: ./scripts/deploy-phase1.sh apply"
        echo "=========================================="
    fi
}

main
