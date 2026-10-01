# Remote state. Created by bootstrap.sh / bootstrap.bat before the first init.
#   S3       — stores terraform.tfstate, versioned and encrypted
#   DynamoDB — state locking, prevents two applies running at once

terraform {
  backend "s3" {
    bucket         = "research-agent-tfstate-696155685592"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "research-agent-tf-locks"
    encrypt        = true
    profile        = "demo"
  }
}
