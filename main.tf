terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

#Pulling a list of all the Availabiltiy zones in us-east-2
data "aws_availability_zones" "available" {
  state = "available"
}

#Creating a vpc resource with a cidr block of 10.0.0.0/16
resource "aws_vpc" "myvpc" {

  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "myvpc"
  }

}

#Creating an Internet Gateway for my vpc
resource "aws_internet_gateway" "myigw" {

  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "myigw"
  }
}

#Creating 2 Public subnets for my web tier
resource "aws_subnet" "public_subnets" {

  count = 2

  vpc_id                  = aws_vpc.myvpc.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = var.public_subnet_cidr[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = var.public_subnet_names[count.index]
  }
}

#Creating a route table for my public subnets and vpc
resource "aws_route_table" "web_route" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myigw.id
  }

  tags = {
    Name = "web_route"
  }
}

#Associating my Public Subnets to my web route table
resource "aws_route_table_association" "web_rt_subs" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets.*.id[count.index]
  route_table_id = aws_route_table.web_route.id
}

#Creating 2 Private Subnets for my Data tier
resource "aws_subnet" "private_subnets" {

  count = 2

  vpc_id            = aws_vpc.myvpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = var.private_subnet[count.index]

  tags = {
    Name = var.private_subnet_names[count.index]
  }
}

#Creating a route table for my Database tier
resource "aws_route_table" "db_route" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "db_route"
  }
}

#Associating my Private Subnets to my Database Route table
resource "aws_route_table_association" "db_rt_subs" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets.*.id[count.index]
  route_table_id = aws_route_table.db_route.id
}

#Creating a Security Group that will allow access via http and ssh
resource "aws_security_group" "public_sg" {

  name   = "web-server-sg"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
  }

  ingress {
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }

}

#Creating 2 ec2 instances the will be located in two seperate Public subnets and availability zones
resource "aws_instance" "ec2_instance" {

  count = 2

  ami                    = "ami-0beaa649c482330f7"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [resource.aws_security_group.public_sg.id]
  subnet_id              = aws_subnet.public_subnets.*.id[count.index]

  tags = {
    Name = var.instance_names[count.index]
  }

  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd.service
        systemctl enable httpd.service
        echo "<html><body><h2>WITNESS THE POWER OF TERRAFORM</h2></body></html>" > /var/www/html/index.html
        EOF

}

#Creating a Load Balancing Target for my Application Load Balancer
resource "aws_lb_target_group" "lb_target" {

  name     = "lb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id
}

#Creating a load balancer listner for my Application Load Balancer
resource "aws_lb_listener" "lb_listener" {

  load_balancer_arn = aws_lb.web_lb.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_target.arn
  }
}

#Creating my Application Load Balancer for my Ec2 Instances
resource "aws_lb" "web_lb" {

  name               = "web-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_sg.id]
  subnets            = aws_subnet.public_subnets.*.id

  tags = {
    name = "web_lb"
  }
}

#Attaching my 2 EC2 Instances to my Application Load Balancer
resource "aws_lb_target_group_attachment" "tg_attachment" {

  count = 2

  target_group_arn = aws_lb_target_group.lb_target.arn
  target_id        = aws_instance.ec2_instance.*.id[count.index]
  port             = 80
}

#Creating a Subnet Group for my Data tier
resource "aws_db_subnet_group" "db_subnet_group" {

  subnet_ids = aws_subnet.private_subnets.*.id
}

#Creating a Security Group for my Data Tier that open on port 3306 from public sg 
resource "aws_security_group" "db_sg" {
  name        = "db_sg"
  description = "allow traffic only from web_sg"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
    cidr_blocks     = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Creating my Database mysql Instance in Availabiltiy Zone us-east-2a
resource "aws_db_instance" "mysql_db" {
  allocated_storage   = 10
  identifier          = "mysql-db"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t2.micro"
  multi_az            = false
  availability_zone   = data.aws_availability_zones.available.names[0]
  username            = var.username
  password            = var.password
  skip_final_snapshot = true

}

