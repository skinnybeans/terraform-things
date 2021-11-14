terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "prod/data-stores/mysql/terraform.tfstate"
    region = "ap-southeast-2"

    dynamodb_table = "terraform-locks-skinnybeans"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

module "database" {
  source = "../../../modules/data-stores/mysql"
  db_admin_password_parameter = "/prod/data-stores/mysql/admin-password"
  db_cluster_identifier = "prod-mysql"
}

output "address" {
  value       = module.database.address
  description = "Connect to the database at this endpoint"
}

output "port" {
  value       = module.database.port
  description = "The port the database is listening on"
}