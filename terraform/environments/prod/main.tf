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

# We declare your public key so AWS knows it
resource "aws_key_pair" "admin_key" {
  key_name   = "admin-key-3tier"
  public_key = file("~/.ssh/id_ovh.pub")
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
    values = ["AWS-3Tier-App"]
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
    values = ["AWS-3Tier-App"]
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
    values = ["AWS-3Tier-App"]
  }
}

# --- 2. SECURITY GROUPS ---

# SG 1: Load Balancer (Public)
resource "aws_security_group" "lb_sg" {
  name        = "aws-3tier-lb-sg"
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
  name        = "aws-3tier-web-sg"
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
  name        = "aws-3tier-app-sg"
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
  name        = "aws-3tier-db-sg"
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
  name               = "aws-3tier-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "web_tg" {
  name     = "aws-3tier-web-tg"
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
  count         = 2
  ami           = data.aws_ami.web.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.admin_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  # App IP Injection + Dynamic HTML Creation
  user_data = <<-EOF
              #!/bin/bash
              # 1. Configure Nginx with App IP
              sed -i 's/APP_IP_PLACEHOLDER/${aws_instance.app[0].private_ip}/g' /etc/nginx/sites-available/default
              systemctl restart nginx

              # 2. Create Web page with JS calling the API
              cat <<EOT > /var/www/html/index.html
              <!DOCTYPE html>
              <html>
              <head>
                  <style>
                      body { font-family: sans-serif; text-align: center; padding-top: 50px; background: #f0f0f0; }
                      .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); display: inline-block; }
                      h1 { color: #333; }
                      .db-msg { color: blue; font-weight: bold; font-size: 1.2em; }
                  </style>
              </head>
              <body>
                  <div class="card">
                      <h1>3-Tier Architecture</h1>
                      <p>Web Server: <strong>$(hostname)</strong></p>
                      <hr>
                      <p>Message from DB (via App Tier):</p>
                      <div id="db-data" class="db-msg">Loading...</div>
                  </div>

                  <script>
                    fetch('/api/message')
                      .then(r => r.json())
                      .then(data => {
                          document.getElementById('db-data').innerText = data.message;
                      })
                      .catch(err => {
                          document.getElementById('db-data').innerText = "Error connecting to API";
                          document.getElementById('db-data').style.color = "red";
                      });
                  </script>
              </body>
              </html>
              EOT
              EOF

  tags = { Name = "AWS-3Tier-Web-${count.index}" }
}

# App Servers (x1)
resource "aws_instance" "app" {
  count                  = 1
  ami                    = data.aws_ami.app.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.admin_key.key_name
  
  # ROBUST FIX:
  # 1. Create .env file
  # 2. Change permissions to ensure app can read it
  # 3. Explicitly restart the service
  user_data = <<-EOF
              #!/bin/bash
              echo "DB_HOST=${aws_instance.db[0].private_ip}" > /opt/myapp/.env
              chmod 644 /opt/myapp/.env
              systemctl daemon-reload
              systemctl restart myapp
              EOF

  tags = { Name = "AWS-3Tier-App" }
}

# DB Servers (x2)
resource "aws_instance" "db" {
  count                  = 2
  ami                    = data.aws_ami.db.id
  instance_type          = "t3.micro"
  key_name      = aws_key_pair.admin_key.key_name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  
  tags = {
    Name = "AWS-3Tier-DB-${count.index}"
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