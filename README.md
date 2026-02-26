# DMAIIN - Digital Multi-Agent Academic Integrity Intelligence Network

**Phase 1: Cloud-Native Assignment Submission Portal (v4.5.1)**

A secure, FERPA-compliant assignment submission system built on AWS serverless architecture. Phase 1 delivers authentication, file upload, metadata tracking, and a full audit trail.

---

## Architecture

```
                           +-------------------+
                           |   React Frontend  |
                           |  (S3 Static Site) |
                           +--------+----------+
                                    |
                                    | HTTPS
                                    v
                           +-------------------+
                           |    AWS WAF v2     |
                           | (Rate Limiting +  |
                           |  Managed Rules)   |
                           +--------+----------+
                                    |
                                    v
                           +-------------------+
                           | API Gateway REST  |
                           | (Cognito Auth)    |
                           +--------+----------+
                                    |
                    +---------------+---------------+
                    |               |               |
                    v               v               v
            +-------+----+  +------+------+  +-----+--------+
            |  intake-   |  | get-submis- |  | get-submis-  |
            |  handler   |  | sion-meta   |  | sion-status  |
            |  (Lambda)  |  | data        |  |  (Lambda)    |
            +------+-----+  | (Lambda)    |  +--------------+
                   |        +------+------+
                   |               |
          +--------+--------+     |
          |        |        |     |
          v        v        v     v
     +----+--+ +--+---+ +--+-----+-+
     |  S3   | | Dyna | | audit-   |
     | (raw) | | moDB | | logger   |
     +-------+ +------+ | (Lambda) |
                         +----+-----+
                              |
                              v
                        +-----+------+
                        |  DynamoDB  |
                        | (audit_log)|
                        +------------+

     +------------------+    +------------------+
     |   CloudTrail     |    |   CloudWatch     |
     | (S3 Data Events) |    | (Dashboard +     |
     +------------------+    |  Alarms)         |
                             +------------------+

     +------------------+
     |   KMS Key        |
     | (Encryption at   |
     |  Rest for All)   |
     +------------------+
```

### Components

| Component | Technology | Purpose |
|---|---|---|
| Frontend | React 18 + TypeScript + Tailwind CSS | Single-page application with drag-and-drop upload |
| Authentication | Amazon Cognito | User pools with Students/Faculty/Admin groups |
| API Layer | API Gateway REST + WAF v2 | Rate-limited API with Cognito authorizer |
| Upload Processing | Lambda (Python 3.11) | Multipart form parsing, validation, S3 storage |
| Metadata Store | DynamoDB (PAY_PER_REQUEST) | Submission records with GSIs for queries |
| File Storage | S3 with KMS encryption | Versioned buckets with Object Lock (GOVERNANCE) |
| Audit Trail | Lambda + DynamoDB + CloudTrail | 7-year retention for FERPA compliance |
| Monitoring | CloudWatch Dashboard + Alarms | 5 metric widgets, error alerting |
| Infrastructure | Terraform (~14 .tf files) | Fully declarative IaC |

---

## Prerequisites

- **AWS Account** with administrative access
- **AWS CLI** v2 configured with credentials (`aws configure`)
- **Terraform** >= 1.5.0
- **Node.js** >= 20 and npm
- **Python** 3.11+ and pip
- **Git**

### Verify Prerequisites

```bash
aws --version
terraform version
node --version
python3 --version
aws sts get-caller-identity
```

---

## Project Structure

```
.
├── .github/workflows/
│   └── deploy.yml              # CI/CD pipeline
├── frontend/
│   ├── public/index.html       # HTML template
│   ├── src/
│   │   ├── App.tsx             # Main app with routing and auth context
│   │   ├── index.tsx           # Entry point
│   │   ├── index.css           # Tailwind imports
│   │   ├── components/
│   │   │   ├── Login.tsx       # Login/Register/Confirm views
│   │   │   ├── FileUpload.tsx  # Drag-and-drop file upload
│   │   │   ├── UploadProgress.tsx # Progress bar
│   │   │   └── SubmissionList.tsx # Submissions table with auto-refresh
│   │   └── services/
│   │       ├── auth.ts         # Amplify v6 auth wrapper
│   │       └── api.ts          # Axios API client
│   ├── package.json
│   ├── tailwind.config.js
│   └── tsconfig.json
├── lambda/
│   ├── intake-handler/         # POST /submissions/upload
│   │   ├── lambda_function.py
│   │   ├── requirements.txt
│   │   └── tests/
│   │       └── test_handler.py # Unit tests (moto + pytest)
│   ├── get-submission-metadata/ # GET /submissions/{id}
│   │   ├── lambda_function.py
│   │   └── requirements.txt
│   ├── get-submission-status/  # GET /submissions/{id}/status
│   │   ├── lambda_function.py
│   │   └── requirements.txt
│   └── audit-logger/          # Async audit event writer
│       ├── lambda_function.py
│       └── requirements.txt
├── scripts/
│   ├── deploy-phase1.sh       # Master deployment script
│   ├── setup-cognito-users.sh # Create test users
│   └── cleanup.sh             # Tear down all resources
├── terraform/
│   ├── provider.tf            # AWS provider + backend config
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output values
│   ├── kms.tf                 # Encryption key
│   ├── iam.tf                 # IAM roles and policies
│   ├── cognito.tf             # User pool, client, groups
│   ├── s3.tf                  # Storage buckets (raw, processed, reports, frontend)
│   ├── dynamodb.tf            # Tables (submissions, audit_log)
│   ├── lambda.tf              # Functions, DLQ, log groups
│   ├── apigateway.tf          # REST API, methods, CORS, deployment
│   ├── waf.tf                 # WAF rules and rate limiting
│   ├── cloudtrail.tf          # Audit trail with S3 data events
│   ├── cloudwatch.tf          # Dashboard and alarms
│   └── terraform.tfvars.example
├── tests/integration/
│   ├── test_upload_flow.py    # End-to-end upload tests
│   ├── test_authentication.py # Auth and authorization tests
│   └── sample_files/          # Test fixtures
└── .gitignore
```

---

## Deployment Guide

### Step 1: Clone and Configure

```bash
git clone <repository-url>
cd Digital-Multi-Agent-Academic-Integrity-Intelligence-Network

# Copy and edit Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your settings
```

Key variables in `terraform.tfvars`:

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region for all resources |
| `environment` | `dev` | Environment name (dev/staging/prod) |
| `project_name` | `dmaiin` | Prefix for resource naming |
| `frontend_origin` | `*` | CORS origin (restrict in production) |
| `lambda_memory_mb` | `512` | Lambda memory allocation |
| `max_upload_size_bytes` | `52428800` | Max upload size (50 MB) |
| `cloudtrail_retention_days` | `2555` | Log retention (7 years for FERPA) |

### Step 2: Deploy Infrastructure

**Option A: Using the deployment script (recommended)**

```bash
chmod +x scripts/deploy-phase1.sh

# Preview changes
./scripts/deploy-phase1.sh plan

# Deploy everything
./scripts/deploy-phase1.sh apply
```

**Option B: Manual deployment**

```bash
# Package Lambda functions
for dir in lambda/*/; do
  if [ -f "${dir}requirements.txt" ]; then
    pip3 install -r "${dir}requirements.txt" -t "${dir}package/"
  else
    mkdir -p "${dir}package/"
  fi
  cp "${dir}lambda_function.py" "${dir}package/"
  (cd "${dir}package" && zip -r -q "../package.zip" .)
  rm -rf "${dir}package/"
done

# Deploy Terraform
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Note the outputs
terraform output
```

### Step 3: Build and Deploy Frontend

```bash
cd frontend
npm install

# Set environment variables from Terraform outputs
export REACT_APP_API_URL=$(cd ../terraform && terraform output -raw api_gateway_url)
export REACT_APP_COGNITO_USER_POOL_ID=$(cd ../terraform && terraform output -raw cognito_user_pool_id)
export REACT_APP_COGNITO_CLIENT_ID=$(cd ../terraform && terraform output -raw cognito_user_pool_client_id)
export REACT_APP_AWS_REGION=$(cd ../terraform && terraform output -raw aws_region)

npm run build

# Deploy to S3
BUCKET=$(cd ../terraform && terraform output -raw frontend_bucket_name)
aws s3 sync build/ "s3://${BUCKET}/" --delete
```

### Step 4: Create Test Users

```bash
chmod +x scripts/setup-cognito-users.sh
./scripts/setup-cognito-users.sh
```

This creates three test users:

| User | Email | Password | Group |
|---|---|---|---|
| Student | student@test.edu | Student1!Pass | Students |
| Faculty | faculty@test.edu | Faculty1!Pass | Faculty |
| Admin | admin@test.edu | Admin1!Pass | Admin |

### Step 5: Verify Deployment

Open the frontend URL from Terraform outputs:

```bash
cd terraform && terraform output frontend_url
```

Log in with one of the test credentials and upload a file to verify the pipeline.

---

## Testing

### Unit Tests (Lambda)

```bash
pip install pytest moto boto3

# Run intake-handler tests
cd lambda/intake-handler
PYTHONPATH=. pytest tests/ -v
```

The intake-handler test suite covers:
- Successful file upload (PDF, all 12 allowed types)
- SHA-256 hash verification
- Invalid file extension rejection (.exe, .zip, .png, .xlsx, no extension)
- File size limit enforcement (413 for oversized files)
- Missing form fields (400)
- Empty body handling
- Wrong content-type handling
- CORS preflight (OPTIONS)

### Integration Tests

```bash
pip install boto3 requests

# Run after deployment
./scripts/deploy-phase1.sh test

# Or run individually
python3 tests/integration/test_upload_flow.py
python3 tests/integration/test_authentication.py
```

**Upload flow tests** (10 tests):
1. Upload 5 valid files (PDF, TXT, PY, Java, HTML) and verify 200
2. Upload 5 invalid files (.exe, .dll, .bat, .sh, .bin) and verify 400
3. Verify submissions exist in DynamoDB
4. Verify audit log entries are created

**Authentication tests** (5 tests):
1. Sign in with valid credentials
2. Sign in with invalid credentials (expect rejection)
3. Access API without token (expect 401/403)
4. Access API with valid token (expect 200/404)
5. Student cannot access another student's submission (expect 403)

---

## Security

### Encryption
- **At rest**: KMS customer-managed key (CMK) with automatic rotation for S3, DynamoDB, SQS, and CloudWatch
- **In transit**: HTTPS enforced via API Gateway and S3 bucket policies

### Access Control
- **Cognito** user pool with email verification and strong password policy
- **Role-based access**: Students (own submissions only), Faculty (read all), Admin (full access)
- **API Gateway** Cognito authorizer validates JWT on every request

### WAF Protection
- Rate limiting: 10 uploads per 5 minutes, 500 reads per 5 minutes
- AWS Managed Rules (Common Rule Set) for OWASP protection

### Compliance
- **FERPA**: 7-year audit log retention, Object Lock on raw submissions
- **CloudTrail**: S3 data event logging on the raw submissions bucket
- All Lambda functions include structured JSON logging

### File Validation
- Whitelist of 12 allowed extensions: `.pdf`, `.docx`, `.txt`, `.py`, `.java`, `.cpp`, `.c`, `.js`, `.html`, `.css`, `.ipynb`, `.tex`
- 50 MB file size limit enforced at Lambda and API Gateway levels
- SHA-256 hash computed and stored for integrity verification

---

## CI/CD

The GitHub Actions workflow (`.github/workflows/deploy.yml`) provides:

**On pull request to main:**
- Run Lambda unit tests (pytest)
- Build frontend (npm build)

**On push to main:**
- All of the above, plus:
- Package Lambda functions
- Terraform init/validate/plan/apply
- Build frontend with Terraform output values
- Deploy frontend to S3

### Required GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_REGION` | (Optional) Defaults to us-east-1 |

---

## Cleanup

To destroy all resources:

```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

This script:
1. Empties all S3 buckets (including versioned objects)
2. Runs `terraform destroy` to remove all infrastructure

Alternatively:

```bash
./scripts/deploy-phase1.sh destroy
```

---

## Troubleshooting

### Common Issues

**"No valid credential sources found"**
```
aws configure
# Or set environment variables:
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

**Terraform state lock error**
```bash
# If a previous run was interrupted
terraform force-unlock <LOCK_ID>
```

**Lambda deployment package too large**
- Ensure you're not including test files or `__pycache__` in the zip
- The deploy script only packages `lambda_function.py` and `requirements.txt` dependencies

**CORS errors in browser**
- Verify `frontend_origin` in `terraform.tfvars` matches your frontend URL
- Check that OPTIONS methods are deployed (should be automatic)
- For development, `frontend_origin = "*"` is acceptable

**Cognito "User does not exist" error**
- Run `./scripts/setup-cognito-users.sh` to create test users
- Verify the User Pool ID matches between frontend env vars and Terraform outputs

**S3 bucket deletion fails (BucketNotEmpty)**
- Use `./scripts/cleanup.sh` which empties buckets before destroying
- For versioned buckets, all versions and delete markers must be removed

**API Gateway 403 "Missing Authentication Token"**
- Ensure you're sending the `Authorization` header with the Cognito ID token
- Check that the API Gateway stage is deployed (the Terraform config auto-deploys)

**Lambda timeout on file upload**
- Default timeout is 30 seconds for intake-handler
- For very large files, increase `lambda_timeout_seconds` in `terraform.tfvars`
- Check CloudWatch logs: `/aws/lambda/dmaiin-dev-intake-handler`

### Viewing Logs

```bash
# Lambda logs
aws logs tail /aws/lambda/dmaiin-dev-intake-handler --follow

# All Lambda functions
for fn in intake-handler get-submission-metadata get-submission-status audit-logger; do
  echo "=== dmaiin-dev-${fn} ==="
  aws logs tail "/aws/lambda/dmaiin-dev-${fn}" --since 1h
done
```

---

## Cost Estimation

All resources use serverless/on-demand pricing. Estimated monthly costs at low-to-moderate usage:

| Service | Free Tier | Estimated Cost (post-free-tier) |
|---|---|---|
| Lambda | 1M requests/month | ~$0.20 per 1M additional requests |
| API Gateway | 1M calls/month | ~$3.50 per 1M additional calls |
| DynamoDB | 25 GB storage, 25 WCU/RCU | ~$1.25 per million write requests |
| S3 | 5 GB storage | ~$0.023/GB/month |
| Cognito | 50,000 MAU free | Free for most academic use |
| KMS | 1 CMK | ~$1.00/month + $0.03 per 10K requests |
| WAF | N/A | ~$5.00/month + $0.60 per 1M requests |
| CloudTrail | 1 trail free | Data events: $0.10 per 100K events |
| CloudWatch | Basic free | Dashboard: $3.00/month, Logs: $0.50/GB |

**Estimated total for development/testing: $10-15/month**
**Estimated total for moderate academic use (1000 students): $25-50/month**

Most services fall within the AWS Free Tier for the first 12 months.

---

## Allowed File Types

| Extension | Description |
|---|---|
| `.pdf` | PDF documents |
| `.docx` | Microsoft Word |
| `.txt` | Plain text |
| `.py` | Python source |
| `.java` | Java source |
| `.cpp` | C++ source |
| `.c` | C source |
| `.js` | JavaScript source |
| `.html` | HTML documents |
| `.css` | CSS stylesheets |
| `.ipynb` | Jupyter notebooks |
| `.tex` | LaTeX documents |

---

## API Endpoints

| Method | Path | Auth | Lambda | Description |
|---|---|---|---|---|
| POST | `/submissions/upload` | Cognito | intake-handler | Upload a file |
| GET | `/submissions/{id}` | Cognito | get-submission-metadata | Get submission details |
| GET | `/submissions/{id}/status` | Cognito | get-submission-status | Get submission status |

All endpoints return JSON and include CORS headers. The upload endpoint accepts `multipart/form-data` with fields: `file`, `student_id`, `course_id`, `section_id`.

---

## License

This project is intended for academic use. See your institution's policies for applicable licensing terms.
