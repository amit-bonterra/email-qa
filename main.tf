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
  default = "https://github.com/your-name/email-qa.git"
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

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "node_server" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.node_api_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1
              yum update -y

              # Install Node.js and Git
              curl -sL https://rpm.nodesource.com/setup_18.x | bash -
              yum install -y nodejs git unzip

              # Install PM2 globally
              npm install -g pm2

              # Install AWS CLI
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              ./aws/install

              # Clone your app
              cd /home/ec2-user
              git clone ${var.public_repo} app
              cd app

              # Install node modules
              npm install

              # Create .env with AWS region (modify as needed)
              echo "AWS_REGION=${var.aws_region}" > .env

              # Start the app using PM2
              pm2 start ${var.startup_file} --name=email-api
              pm2 save
              pm2 startup systemd -u ec2-user --hp /home/ec2-user | grep sudo | bash
              EOF

  tags = {
    Name = "NodeJS-Email-Extractor"
  }
}

output "public_ip" {
  value       = aws_instance.node_server.public_ip
  description = "Public IP of your API server"
}