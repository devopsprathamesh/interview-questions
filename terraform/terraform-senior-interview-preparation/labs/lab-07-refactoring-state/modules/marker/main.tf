variable "environments" {
  type = list(string)
}

resource "aws_ssm_parameter" "environment_marker" {
  for_each = toset(var.environments)

  name  = "/lab-07/${each.key}/marker"
  type  = "String"
  value = "managed-by-terraform-${each.key}"
}

output "parameter_names" {
  value = { for env, param in aws_ssm_parameter.environment_marker : env => param.name }
}
