terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "prod/services/webserver-cluster/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

module "webserver_cluster" {
  source = "../../../modules/services/webserver-cluster"

  cluster_name = "webservers-prod"
  db_remote_state_bucket = "terraform-state-skinnybeans"
  db_remote_state_key = "prod/data-stores/mysql/terraform.tfstate"
}