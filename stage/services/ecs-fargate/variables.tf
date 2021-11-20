variable "name" {
  description = "name of task to run in ECS"
  type        = string
  default     = "testtask"
}

variable "environment" {
  type    = string
  default = "stage"
}

// ENV vars to inject into container
variable "container_environment" {
  type    = string
  default = ""
}

variable "container_image" {
  type    = string
  default = "nginx"
}

variable "container_port" {
  type    = number
  default = 80
}