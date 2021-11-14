data "aws_ssm_parameter" "db_password" {
    name = var.db_admin_password_parameter
}

resource "aws_db_instance" "mysql" {
    identifier_prefix   = var.db_cluster_identifier
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
