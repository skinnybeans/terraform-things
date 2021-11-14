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

resource "aws_instance" "test_server" {
  ami                    =    "ami-0567f647e75c7bc05"
  instance_type          = "t2.micro"
  user_data              = file("${path.module}/user-data.sh")
  vpc_security_group_ids = [ aws_security_group.web_http.id ]
}

resource "aws_security_group" "web_http" {
  name = "web-ingress-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "http-ingress"
  }
}