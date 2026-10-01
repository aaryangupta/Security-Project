@echo off
setlocal enabledelayedexpansion

REM One-time Terraform backend setup: S3 state bucket + DynamoDB lock table.
REM Usage:  bootstrap.bat [profile] [region]
REM Default profile is "demo" to match terraform/backend.tf and providers.tf.

set PROFILE=%1
if "%PROFILE%"=="" set PROFILE=demo

set REGION=%2
if "%REGION%"=="" set REGION=us-east-1

set TABLE=research-agent-tf-locks

echo Using AWS profile : %PROFILE%
echo Using region      : %REGION%
echo.

REM ---- Verify credentials before creating anything ----
set ACCOUNT=
for /f "delims=" %%A in ('aws sts get-caller-identity --profile %PROFILE% --query Account --output text 2^>nul') do set ACCOUNT=%%A

if "!ACCOUNT!"=="" (
    echo ERROR: could not authenticate with AWS profile "%PROFILE%".
    echo.
    echo Fix it with:  aws configure --profile %PROFILE%
    echo Then check:   aws sts get-caller-identity --profile %PROFILE%
    exit /b 1
)

echo Authenticated to AWS account: !ACCOUNT!

REM Bucket names are globally unique across all of AWS, so scope it by account.
set BUCKET=research-agent-tfstate-!ACCOUNT!
echo State bucket      : !BUCKET!
echo.

REM ---- S3 bucket ----
echo Creating S3 bucket: !BUCKET!
if /i "%REGION%"=="us-east-1" (
    aws s3api create-bucket --bucket !BUCKET! --region %REGION% --profile %PROFILE% >nul 2>nul
) else (
    aws s3api create-bucket --bucket !BUCKET! --region %REGION% --create-bucket-configuration LocationConstraint=%REGION% --profile %PROFILE% >nul 2>nul
)
if !errorlevel! equ 0 (
    echo   Bucket created.
) else (
    echo   Bucket already exists or is owned by you, continuing.
)

echo Enabling versioning...
aws s3api put-bucket-versioning --bucket !BUCKET! --versioning-configuration Status=Enabled --profile %PROFILE%
if !errorlevel! neq 0 goto :bucketfail

echo Blocking public access...
aws s3api put-public-access-block --bucket !BUCKET! --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true --profile %PROFILE%

echo Enabling server-side encryption...
aws s3api put-bucket-encryption --bucket !BUCKET! --server-side-encryption-configuration "{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}" --profile %PROFILE%

REM ---- DynamoDB lock table ----
echo Creating DynamoDB table for state locking: %TABLE%
aws dynamodb create-table --table-name %TABLE% --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region %REGION% --profile %PROFILE% >nul 2>nul
if !errorlevel! equ 0 (
    echo   DynamoDB table created.
) else (
    echo   DynamoDB table already exists, continuing.
)

echo.
echo Bootstrap complete.
echo   AWS account : !ACCOUNT!
echo   S3 bucket   : !BUCKET! ^(versioned, encrypted, private^)
echo   DynamoDB    : %TABLE% ^(state locking^)
echo.
echo Confirm terraform\backend.tf matches:
echo     bucket  = "!BUCKET!"
echo     profile = "%PROFILE%"
echo.
echo Next step: cd terraform  then  terraform init  then  terraform apply

endlocal
exit /b 0

:bucketfail
echo.
echo ERROR: the bucket exists but is not accessible from account !ACCOUNT!.
echo S3 bucket names are global, so another AWS account may already own this name.
echo Pick a different name in this script and in terraform\backend.tf.
endlocal
exit /b 1
