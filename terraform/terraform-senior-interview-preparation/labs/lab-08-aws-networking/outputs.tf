output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "nat_gateway_ids" {
  value = module.vpc.nat_gateway_ids
}

output "app_security_group_id" {
  value = module.app_security_group.security_group_id
}

output "alb_security_group_id" {
  value = module.alb_security_group.security_group_id
}

output "interface_endpoint_ids" {
  value = { for k, ep in aws_vpc_endpoint.interface : k => ep.id }
}
