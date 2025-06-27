provider "aws" {
  region  = "us-east-1"
  profile = "terraform-user" # or your named AWS CLI profile
}

resource "aws_key_pair" "deployer" {
  key_name   = "ec2-fastapi-key"
  public_key = file("~/.ssh/id_rsa.pub") # Ensure this key exists
}

resource "aws_security_group" "ec2_sg" {
  name_prefix = "api-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # API
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ollama_api" {
  ami                    = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.key_name
  security_groups        = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt update && apt install -y python3 git curl python3-pip python3-venv

    # Create working dir
    mkdir -p /app
    cd /app

    # Clone your repo (replace with your actual repo)
    git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git .
    
    # Python venv
    python3 -m venv venv
    source venv/bin/activate

    # Python deps
    pip install --upgrade pip
    pip install -r requirements.txt

    # Install Ollama
    curl -fsSL https://ollama.com/install.sh | sh
    nohup ollama serve > /dev/null 2>&1 &
    sleep 10
    ollama run mistral

    # Set env vars
    echo "export OLLAMA_MODEL=mistral" >> ~/.bashrc
    echo "export OLLAMA_HOST=http://localhost:11434" >> ~/.bashrc
    export OLLAMA_MODEL=mistral
    export OLLAMA_HOST=http://localhost:11434

    # Start API
    nohup venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 &
  EOF

  tags = {
    Name = "ollama-fastapi"
  }
}