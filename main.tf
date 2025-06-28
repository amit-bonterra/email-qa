provider "aws" {
  region = var.aws_region
  profile = var.aws_profile
}

variable "aws_region" {
  default = "us-east-1"
}

variable "aws_profile" {
  default = "terraform-user"
}

# 🔁 Replace this with your actual EC2 Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/email_qa.pub")  # You must have this key locally
}

# 🔁 Public GitHub repo URL (HTTPS only)
variable "public_repo" {
  default = "https://github.com/amit-bonterra/email-qa.git"
}

# If your entry point is in a subfolder like src/app.js
variable "startup_file" {
  default = "src/app.js"
}

variable "allowed_ip" {
  default = "0.0.0.0/0"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "node_api_sg" {
  name        = "node-api-sg"
  description = "Allow SSH and API access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ip]
  }

  ingress {
    description = "API access"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "node_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.node_api_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1

              # Update and install essentials
              sudo apt update -y
              sudo apt install -y curl git unzip

              # Install Node.js and npm
              curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
              sudo apt install -y nodejs

              # Install pm2 globally
              sudo npm install -g pm2

              # Clone your app
              cd /home/ubuntu
              git clone ${var.public_repo} app
              cd app
              export HOME=/home/ubuntu

              # Install app dependencies
              npm install

              # Create .env with AWS region
              echo "AWS_REGION=${var.aws_region}" > .env

              # PM2 startup and app launch
              sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
              pm2 start ${var.startup_file} --name=email-api
              pm2 save

              EOF

  tags = {
    Name = "NodeJS-Email-Extractor"
  }
}

output "public_ip" {
  value       = aws_instance.node_server.public_ip
  description = "Public IP of your API server"
}