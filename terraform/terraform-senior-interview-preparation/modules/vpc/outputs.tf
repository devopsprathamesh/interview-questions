output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by availability zone. Guaranteed present for every AZ passed in availability_zones."
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }

  precondition {
    condition     = length(aws_subnet.public) == length(var.availability_zones)
    error_message = "Expected one public subnet per availability zone."
  }
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by availability zone. Guaranteed present for every AZ passed in availability_zones."
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }

  precondition {
    condition     = length(aws_subnet.private) == length(var.availability_zones)
    error_message = "Expected one private subnet per availability zone."
  }
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Private route table IDs keyed by availability zone."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by availability zone (empty map if nat_strategy = \"none\")."
  value       = { for az, nat in aws_nat_gateway.this : az => nat.id }
}
