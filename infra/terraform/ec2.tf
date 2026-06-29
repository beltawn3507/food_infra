#Region

provider "aws" {
        region = "ap-south-1"
}

#VPC Default use

resource aws_default_vpc default{
}

#Security Group

resource aws_security_group my_security_group{
name = "terraform-security-group"
description = "This is inbound and outbound rules"
}

resource aws_vpc_security_group_ingress_rule allow_http {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  ip_protocol = "tcp"
  to_port = 80
}

resource aws_vpc_security_group_ingress_rule allow_ssh {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource aws_vpc_security_group_egress_rule allow_all_traffic {
  security_group_id = aws_security_group.my_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource aws_instance my_instance {
        ami = "ami-01a00762f46d584a1"
        instance_type = "m7i-flex.large"
        key_name = "new-key"
        vpc_security_group_ids = [aws_security_group.my_security_group.id]
        user_data = file("${path.module}/bootstrap.sh")
        user_data_replace_on_change = true
        root_block_device {
                volume_size = 10
                volume_type = "gp3"
        }
        tags ={
                Name = "food-terra-server"
        }
}

resource "aws_eip" "lb" {
  instance = aws_instance.my_instance.id
  domain   = "vpc"

