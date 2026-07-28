## Minimal, cheap EC2 fixture for Lab 3 (Dynamic Inventory).
## Cost warning: 3x t3.micro instances - a few cents/hour if left running.
## Destroy promptly with `terraform destroy` after the lab.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  instances = {
    web1 = { environment = "dev", role = "webserver" }
    web2 = { environment = "dev", role = "webserver" }
    db1  = { environment = "dev", role = "database" }
  }
}

resource "aws_instance" "lab03" {
  for_each      = local.instances
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name        = "lab03-${each.key}"
    Project     = "ansible-senior-interview-prep"
    Environment = each.value.environment
    Role        = each.value.role
  }
}

output "instance_ids" {
  value = { for k, v in aws_instance.lab03 : k => v.id }
}
