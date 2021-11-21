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
  region = "ap-southeast-2"
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

data "aws_route53_zone" "sorcererdecks" {
  name     = "sorcererdecks.com"
}

##
## Cluster to run task on
##

resource "aws_ecs_cluster" "main" {
  name                = "staging-fargate-cluster"

  tags = {
    Name              = "staging-fargate-cluster"
    Environment       = "staging"
    TerraformManaged  = "true"
  }
}

##
##  NGINX container on ECS cluster
##
module "nginx_ecs" {
  source = "../../../modules/services/ecs-fargate-web"

  ##  AWS general variables
  gen_region            = "ap-southeast-2"
  gen_environment       = "staging"

  ##  Networking
  net_vpc_id                    = data.aws_vpc.default.id
  net_load_balancer_subnet_ids  = data.aws_subnet_ids.default.ids
  net_task_subnet_ids           = data.aws_subnet_ids.default.ids

  ##  SSL cert
  ssl_load_balancer_certificate_arn = data.terraform_remote_state.cert_arn.outputs.sorcerer_cert_arn

  ##  ECS cluster
  cluster_name        = aws_ecs_cluster.main.name
  cluster_id          = aws_ecs_cluster.main.id

  ##  Task
  task_name           = "test-nginx"
  task_cpu            = 256
  task_memory         = 512
  task_container_environment    = ""
  task_container_image          = "nginx"
  task_container_image_tag      = "latest"
  task_container_port = 80

  ##  Service
  service_addition_sg_ids       = []

  ##  Load balancer
  lb_min_capacity = 2
  lb_max_capacity = 4
}

##
##  Route53 entry for the NGINX fronting LB
##
resource "aws_route53_record" "nginx_url" {
  zone_id = data.aws_route53_zone.sorcererdecks.zone_id
  name    = "nginx.${data.aws_route53_zone.sorcererdecks.name}"
  type    = "A"
  alias {
    name      = module.nginx_ecs.lb_dns_name
    zone_id   = module.nginx_ecs.lb_dns_zone_id
    evaluate_target_health = true
  }
}