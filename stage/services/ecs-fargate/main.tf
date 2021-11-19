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

// TODO: read from SSM parameters
data "aws_vpc" "default" {
  default = true
}

// TODO: read from SSM parameters: split into public and private subnets as well
data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

// TODO: change certificate ARN look up
data "terraform_remote_state" "cert_arn" {
  backend = "s3"
  config = {
    bucket = "terraform-state-skinnybeans"
    key    = "stage/shared/certificates/terraform.tfstate"
    region = "ap-southeast-2"
  }
}

##
## Security groups
##
resource "aws_security_group" "web_task" {
  name    = "ecs-task-sg"

  ingress {
    description   = "traffic from LB to ECS task"
    from_port     = 80
    to_port       = 80
    protocol      = "tcp"
    self          = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_lb" {
  name    = "public-lb-sg"

  ingress {
    description   = "HTTPS traffic from public"
    from_port     = 443
    to_port       = 443
    protocol      = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

##
## Cluster
##
resource "aws_ecs_cluster" "main" {
  name                = "ecs-stage"
}

##
## Cloudwatch log group for task
##
resource "aws_cloudwatch_log_group" "task_logs" {
  name = "stage/services/ecs-fargate"

  retention_in_days = 1

  tags = {
    Environment = "stage"
    Application = "ecs-fargate"
  }
}


##
## Task and service set up
##
resource "aws_ecs_task_definition" "main" {
  family                    = "service"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  cpu                       = 256
  memory                    = 512
  execution_role_arn        = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn             = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name        = "${var.name}-container-${var.environment}"
      image       = "${var.container_image}:latest"
      essential   = true
      // environment = var.container_environment
      portMappings = [{
        protocol      = "tcp"
        containerPort = var.container_port
        hostPort      = var.container_port
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "stage/services/ecs-fargate"
          awslogs-stream-prefix = "nginx"
          awslogs-region        = "ap-southeast-2"
        }
      }
    }
  ])
}

// Task role for the executing app to do things
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name}-ecsTaskRole"
 
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

// Task execution role to allow fargate to pull and start images
# TODO: add logs:CreateLogGroup permission so can create cloudwatch log group
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name}-ecsTaskExecutionRole"
 
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}
 
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

// Service to run the task
resource "aws_ecs_service" "main" {
  name                               = "${var.name}-service-${var.environment}"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.main.arn
  desired_count                      = 2
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"

  network_configuration {
    security_groups  = [aws_security_group.web_task.id]
    subnets          = data.aws_subnet_ids.default.ids
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.main.arn
    container_name   = "${var.name}-container-${var.environment}"
    container_port   = var.container_port
  }

  // Use this to ignore task definition changes
  // EG if the task is being deployed by the app code repo
  # lifecycle {
  #   ignore_changes = [task_definition, desired_count]
}

##
## Load balancer
##

resource "aws_lb" "main" {
  name               = "${var.name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_lb.id, aws_security_group.web_task.id]
  subnets            = data.aws_subnet_ids.default.ids
 
  enable_deletion_protection = false
}
 
resource "aws_alb_target_group" "main" {
  name        = "${var.name}-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"
 
  health_check {
   healthy_threshold   = "3"
   interval            = "30"
   protocol            = "HTTP"
   matcher             = "200"
   timeout             = "3"
   path                = "/"
   unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.main.id
  port              = 80
  protocol          = "HTTP"

  # default_action {
  #   target_group_arn = aws_alb_target_group.main.id
  #   type             = "forward"
  # }

  default_action {
   type = "redirect"
 
   redirect {
     port        = 443
     protocol    = "HTTPS"
     status_code = "HTTP_301"
   }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_lb.main.id
  port              = 443
  protocol          = "HTTPS"
 
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.terraform_remote_state.cert_arn.outputs.sorcerer_cert_arn
 
  default_action {
    target_group_arn = aws_alb_target_group.main.id
    type             = "forward"
  }
}

##
## Autoscaling
##

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
 
  target_tracking_scaling_policy_configuration {
   predefined_metric_specification {
     predefined_metric_type = "ECSServiceAverageCPUUtilization"
   }
 
   target_value       = 60
  }
}