# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      hashicorp-learn = "expressions"
    }
  }
}

resource "random_id" "id" {
  byte_length = 8
}

locals {
  name  = (var.name != "" ? var.name : random_id.id.hex)
  owner = var.team
  common_tags = {
    Owner = local.owner
    Name  = local.name
  }
}


data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "my_vpc" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = local.common_tags
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags   = local.common_tags
}

resource "aws_subnet" "subnet_public" {
  vpc_id     = aws_vpc.my_vpc.id
  map_public_ip_on_launch = true
  tags   = local.common_tags
  cidr_block = var.cidr_subnet
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.my_vpc.id
  tags   = local.common_tags

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_elb" "learn" {
  name    = "Learn-ELB"
  subnets = [aws_subnet.subnet_public.id]
  tags = local.common_tags
  instances  = aws_instance.ubuntu[*].id
  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400
}


resource "aws_instance" "ubuntu" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  associate_public_ip_address = (count.index == 0 ? true : false)
  subnet_id                   = aws_subnet.subnet_public.id
  tags                        = merge(local.common_tags)
  count                       = (var.high_availability == true ? 3 : 1)
  
  # Security group to allow public access
  vpc_security_group_ids = [aws_security_group.allow_public_access.id]
}

resource "aws_security_group" "allow_public_access" {
  vpc_id = aws_vpc.my_vpc.id
  tags   = local.common_tags

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"] # Replace with your specific IP range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
