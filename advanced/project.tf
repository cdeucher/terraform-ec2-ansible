provider "aws" {
  region     = "us-east-1"
  profile    = "terraform_iam_user"
}

/*
resource "aws_key_pair" "ansible_pub_key" {
  key_name   = "Ansible_local"
  public_key = file("MyKeyPair.pub")
}
*/
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
      Name = "Production-vpc"
  }  
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Production-gateway"
  }
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block   = "::/0"
    gateway_id        = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Production-route_table"
  }
}

resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Production-subnet"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.r.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow Web traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
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

  lifecycle {
      create_before_destroy = true
  }
  
  tags = {
    Name = "Production-table_association"
  }
}

resource "aws_network_interface" "web-server-io" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]
  
  tags = {
    Name = "Production-interface"
  }  
}
# Get the latest Ubuntu Xenial AMI
/*
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}
*/
resource "aws_instance" "web-server-instance" {
  ami               = "ami-02fe94dee086c0c37"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "Ansible_local"

  network_interface{
      device_index = 0
      network_interface_id = aws_network_interface.web-server-io.id
  }
  tags = {
      Name = "Production-instance"
  }
}
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-io.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw, aws_instance.web-server-instance]

  tags = {
    Name = "Production-elastic_IP"
  } 
}

resource "null_resource" "bash_remote" {
  provisioner "remote-exec" {
    connection {
      private_key = file("./keys/MyKeyPair.pem")
      user        = "ubuntu"
      host        = aws_instance.web-server-instance.public_ip
    }

    inline = ["sudo apt update -y", "sudo apt install python3 -y", "echo Done!"]
  }
  # python local to ansible works
  #provisioner "local-exec" {
  #  command = "sudo apt-get update -y && sudo apt-get -qq install python -y"
  #}
  #provisioner "local-exec" {
  #  command = "ANSIBLE_HOST_KEY_CHECKING=False TF_STATE=plan.tfstate ansible-playbook --private-key ${var.pvt_key} apache-install.yml"
  #}
  provisioner "local-exec" {
    command ="ansible-playbook -i ${aws_instance.web-server-instance.public_ip}, --private-key=./keys/MyKeyPair.pem nginx.yaml"
  }
  depends_on = [aws_instance.web-server-instance, aws_eip.one]
}


output "base_ip" {
  value = aws_instance.web-server-instance.public_ip
}




