terraform {
  backend "s3" {
    bucket = "terraform-state-skinnybeans"
    key = "stage/services/webserver-cluster/terraform.tfstate"
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

data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = "terraform-state-skinnybeans"
    key    = "stage/data-stores/mysql/terraform.tfstate"
    region = "ap-southeast-2"
  }
}

resource "aws_launch_configuration" "web_server" {
  image_id =    "ami-0567f647e75c7bc05"
  instance_type = "t2.micro"
  security_groups = [ aws_security_group.web_http.id ]

  user_data = templatefile("user-data.sh", 
    {
      server_port = var.server_port,
      db_address = data.terraform_remote_state.db.outputs.address,
      db_port = data.terraform_remote_state.db.outputs.port
    }
  )

  # tags = {
  #   Name = "terraform-example"
  # }

  # Required when using a launch configuration with an auto scaling group.
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_server.name
  vpc_zone_identifier = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.web_target.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10
  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "web_http" {
  name = "terraform-example-sg"

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "http-ingress"
  }
}

resource "aws_lb" "web_loadbalancer" {
  name                = "terraform-asg-example"
  load_balancer_type  = "application"
  subnets             = data.aws_subnet_ids.default.ids
  security_groups     = [aws_security_group.alb.id]
}
resource "aws_security_group" "alb" {
  name = "terraform-example-alb"

  # Allow inbound HTTP requests
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_loadbalancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn  = aws_lb_listener.http.arn
  priority      = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.web_target.arn
  }
}

resource "aws_lb_target_group" "web_target" {
  name      = "terraform-asg-example"
  port      = var.server_port
  protocol  = "HTTP"
  vpc_id    = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  } 
}