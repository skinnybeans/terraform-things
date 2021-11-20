terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "stage/services/ecs-fargate/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = var.gen_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "terraform_remote_state" "cert_arn" {
  backend = "s3"
  config = {
    bucket = "terraform-state-skinnybeans"
    key    = "stage/shared/certificates/terraform.tfstate"
    region = "ap-southeast-2"
  }
}