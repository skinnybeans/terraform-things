terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "stage/data-stores/mysql/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

data "aws_ssm_parameter" "db_password" {
    name = "/stage/data-stores/mysql/admin-password"
}

resource "aws_db_instance" "mysql" {
    identifier_prefix   = "terraform-up-and-running" 
    engine              = "mysql"
    allocated_storage   = 10
    instance_class      = "db.t2.micro"
    name                = "example_database"
    username            = "admin"
    password            = data.aws_ssm_parameter.db_password.value
    skip_final_snapshot = true
    backup_retention_period = 0
    apply_immediately   = true
}
