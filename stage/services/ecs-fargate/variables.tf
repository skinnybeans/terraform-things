##
##  AWS general variables
##
variable "gen_region" {
  description = "AWS region to use"
  type        = string
  default     = "ap-southeast-2"
}

variable "gen_environment" {
  description = "Prod, stage etc"
  type        = string
}

##
##  Networking
##
variable "vpc_id" {
  description = "VPC to deploy cluster to"
  type        = string
}

variable "load_balancer_subnet_ids" {
  description = "Subnets to deploy load balancer into"
  type        = list
}

variable "task_subnet_ids" {
  description = "Subnets to deploy task into"
  type        = list
}

##
##  SSL cert
##
variable "load_balancer_certificate_arn" {
  description = "SSL certificate ARN to use on loadbalancer"
  type        = string
}

##
##  ECS cluster
##
variable "cluster_name" {
  description = "Name for ECS cluster"
  type        = string
}

##
##  Task
##
variable "task_name" {
  description = "name of task to run in ECS"
  type        = string
  default     = "testtask"
}

variable "task_cpu" {
  description = "CPU allocation for task"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "RAM allocation for task"
  type        = number
  default     = 512
}

variable "container_environment" {
  description = "ENV vars to inject into container environment"
  type    = string
  default = ""
}

variable "container_image" {
  type    = string
  default = "nginx"
}

variable "container_port" {
  description = "Port to expose for container"
  type    = number
  default = 80
}

##
##  Service
##

variable "desired_count" {
  description = "Number of containers to run. Also used for autoscaling min capacity"
  type        = number
  default     = 2
}

##
##  Load balancer
##

variable "max_capacity" {
  description = "Max size to autoscale to"
  type        = number
  default     = 4
}