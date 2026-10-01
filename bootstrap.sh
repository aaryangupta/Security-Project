#!/bin/bash
set -e

# One-time Terraform backend setup: S3 state bucket + DynamoDB lock table.
# Usage:  ./bootstrap.sh [profile] [region]
# Default profile is "demo" to match terraform/backend.tf and providers.tf.

PROFILE="${1:-demo}"
REGION="${2:-us-east-1}"
TABLE="research-agent-tf-locks"

echo "Using AWS profile : $PROFILE"
echo "Using region      : $REGION"
echo ""

# ---- Verify credentials before creating anything ----
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null || true)

if [ -z "$ACCOUNT" ] || [ "$ACCOUNT" = "None" ]; then
  echo "ERROR: could not authenticate with AWS profile \"$PROFILE\"."
  echo ""
  echo "Fix it with:  aws configure --profile $PROFILE"
  echo "Then check:   aws sts get-caller-identity --profile $PROFILE"
  exit 1
fi

echo "Authenticated to AWS account: $ACCOUNT"

# Bucket names are globally unique across all of AWS, so scope it by account.
BUCKET="research-agent-tfstate-${ACCOUNT}"
echo "State bucket      : $BUCKET"
echo ""

# ---- S3 bucket ----
echo "Creating S3 bucket: $BUCKET"
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --profile "$PROFILE" >/dev/null 2>&1 \
    && echo "  Bucket created." || echo "  Bucket already exists or is owned by you, continuing."
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    --profile "$PROFILE" >/dev/null 2>&1 \
    && echo "  Bucket created." || echo "  Bucket already exists or is owned by you, continuing."
fi

echo "Enabling versioning..."
if ! aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile "$PROFILE"; then
  echo ""
  echo "ERROR: the bucket exists but is not accessible from account $ACCOUNT."
  echo "S3 bucket names are global, so another AWS account may already own this name."
  echo "Pick a different name in this script and in terraform/backend.tf."
  exit 1
fi

echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "$PROFILE"

echo "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile "$PROFILE"

# ---- DynamoDB lock table ----
echo "Creating DynamoDB table for state locking: $TABLE"
aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  --profile "$PROFILE" >/dev/null 2>&1 \
  && echo "  DynamoDB table created." || echo "  DynamoDB table already exists, continuing."

echo ""
echo "Bootstrap complete."
echo "  AWS account : $ACCOUNT"
echo "  S3 bucket   : $BUCKET (versioned, encrypted, private)"
echo "  DynamoDB    : $TABLE (state locking)"
echo ""
echo "Confirm terraform/backend.tf matches:"
echo "    bucket  = \"$BUCKET\""
echo "    profile = \"$PROFILE\""
echo ""
echo "Next step: cd terraform && terraform init && terraform apply"
