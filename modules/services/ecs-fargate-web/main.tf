locals {
  # Combine internal defined security group with any additional IDs passed into the module
  service_security_group_ids = length(var.service_addition_sg_ids) > 0 ? concat(var.service_addition_sg_ids, [aws_security_group.web_task.id]) : [aws_security_group.web_task.id]
}

##
## Security groups
##
resource "aws_security_group" "web_task" {
  name    = "${var.gen_environment}-${var.task_name}-task"

  ingress {
    description   = "traffic from LB to ECS task"
    from_port     = var.task_container_port
    to_port       = var.task_container_port
    protocol      = "tcp"
    self          = true
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  
  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-task"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
}

resource "aws_security_group" "web_lb" {
  name    = "${var.gen_environment}-${var.task_name}-lb"

  ingress {
    description   = "HTTPS traffic from public"
    from_port     = 443
    to_port       = 443
    protocol      = "tcp"
    cidr_blocks   = ["0.0.0.0/0"]
  }

  ingress {
    description   = "HTTP traffic from public"
    from_port     = 80
    to_port       = 80
    protocol      = "tcp"
    cidr_blocks   = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-lb"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
}

##
## Cloudwatch log group for task
##
resource "aws_cloudwatch_log_group" "task_logs" {
  name = "${var.gen_environment}/services/"

  retention_in_days = 1

  tags = {
    Name              = "${var.gen_environment}/services/"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
}


##
## Task and service set up
##
resource "aws_ecs_task_definition" "main" {
  family                    = "${var.gen_environment}-${var.task_name}-task"
  network_mode              = "awsvpc"
  requires_compatibilities  = ["FARGATE"]
  cpu                       = var.task_cpu
  memory                    = var.task_memory
  execution_role_arn        = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn             = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([
    {
      name            = "${var.gen_environment}-${var.task_name}-container"
      image           = "${var.task_container_image}:${var.task_container_image_tag}"
      essential       = true
      # TODO: get container environemnt variables working
      #environment     = var.task_container_environment
      portMappings    = [{
        protocol      = "tcp"
        containerPort = var.task_container_port
        hostPort      = var.task_container_port
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "${var.gen_environment}/services/"
          awslogs-stream-prefix = var.task_name
          awslogs-region        = var.gen_region
        }
      }
    }
  ])
  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-task"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
}

// Task role for the executing app to do things
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.gen_environment}-${var.task_name}-taskRole"
  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-taskRole"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
 
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
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.gen_environment}-${var.task_name}-taskExecutionRole"

  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-taskExecutionRole"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
 
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
  name                               = "${var.gen_environment}-${var.task_name}-service"
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.main.arn
  desired_count                      = var.lb_min_capacity
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"

  network_configuration {
    security_groups  = local.service_security_group_ids
    subnets          = var.net_task_subnet_ids
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.main.arn
    container_name   = "${var.gen_environment}-${var.task_name}-container"
    container_port   = var.task_container_port
  }

    tags = {
    Name              = "${var.gen_environment}-${var.task_name}-service"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
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
  name               = "${var.gen_environment}-${var.task_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_lb.id, aws_security_group.web_task.id]
  subnets            = var.net_load_balancer_subnet_ids
 
  enable_deletion_protection = false

  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-alb"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
  }
}
 
resource "aws_alb_target_group" "main" {
  name        = "${var.gen_environment}-${var.task_name}-tg"
  port        = var.task_container_port
  protocol    = "HTTP"
  vpc_id      = var.net_vpc_id
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

  tags = {
    Name              = "${var.gen_environment}-${var.task_name}-tg"
    Environment       = var.gen_environment
    TerraformManaged  = "true"
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
  certificate_arn   = var.ssl_load_balancer_certificate_arn
 
  default_action {
    target_group_arn = aws_alb_target_group.main.id
    type             = "forward"
  }
}

##
## Autoscaling
##

resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.lb_max_capacity
  min_capacity       = var.lb_min_capacity
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.main.name}"
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