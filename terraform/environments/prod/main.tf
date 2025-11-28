terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- 1. DATA SOURCES ---

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "web" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Role"
    values = ["Web"]
  }
  filter {
    name   = "tag:Project"
    values = ["Final-Portfolio"]
  }
}

data "aws_ami" "app" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Role"
    values = ["App"]
  }
  filter {
    name   = "tag:Project"
    values = ["Final-Portfolio"]
  }
}

data "aws_ami" "db" {
  most_recent = true
  owners      = ["self"]
  filter {
    name   = "tag:Role"
    values = ["DB"]
  }
  filter {
    name   = "tag:Project"
    values = ["Final-Portfolio"]
  }
}

# --- 2. SECURITY GROUPS ---

# SG 1: Load Balancer (Public)
resource "aws_security_group" "lb_sg" {
  name        = "portfolio-lb-sg"
  description = "Allow HTTP from Internet"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG 2: Web Tier (Accepts LB only)
resource "aws_security_group" "web_sg" {
  name        = "portfolio-web-sg"
  description = "Allow HTTP from LB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }
  
  # SSH allowed for debug
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG 3: App Tier (Accepts Web only)
resource "aws_security_group" "app_sg" {
  name        = "portfolio-app-sg"
  description = "Allow traffic from Web Tier"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG 4: DB Tier (Accepts App only)
resource "aws_security_group" "db_sg" {
  name        = "portfolio-db-sg"
  description = "Allow traffic from App Tier"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. INFRASTRUCTURE ---

# Load Balancer
resource "aws_lb" "main" {
  name               = "portfolio-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "web_tg" {
  name     = "portfolio-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  
  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Web Servers (x2)
resource "aws_instance" "web" {
  count                  = 2
  ami                    = data.aws_ami.web.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "<h1>Real Server: $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
              
  tags = {
    Name = "Portfolio-Web-${count.index}"
  }
}

# App Servers (x2)
resource "aws_instance" "app" {
  count                  = 2
  ami                    = data.aws_ami.app.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  
  tags = {
    Name = "Portfolio-App-${count.index}"
  }
}

# DB Servers (x2)
resource "aws_instance" "db" {
  count                  = 2
  ami                    = data.aws_ami.db.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  
  tags = {
    Name = "Portfolio-DB-${count.index}"
  }
}

# Attachment
resource "aws_lb_target_group_attachment" "web_attach" {
  count            = 2
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# --- OUTPUT ---

output "load_balancer_url" {
  value = "http://${aws_lb.main.dns_name}"
}