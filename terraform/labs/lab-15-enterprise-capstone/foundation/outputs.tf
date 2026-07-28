output "vpc_id" {
  value = module.vpc.vpc_id
}

output "param_prefix" {
  description = "SSM parameter path prefix other layers read from."
  value       = "/capstone/${var.environment}/foundation"
}
