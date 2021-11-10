terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "global/s3/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-skinnybeans"

  # prevent accidential deletion of the bucket
  lifecycle {
    prevent_destroy = true
  }  

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name          = "terraform-locks-skinnybeans"
  billing_mode  = "PAY_PER_REQUEST"
  hash_key      = "LockID" 

  attribute {
    name = "LockID"
    type = "S"
  }
}
