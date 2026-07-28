package main

# Denies any resource whose provider configuration targets a region outside
# the approved list. Relies on the "region" field Conftest/Terraform's
# plan JSON records per provider configuration (see terraform show -json
# output structure - verify field availability against your Terraform version).

approved_regions := {"us-east-1", "us-west-2", "eu-west-1"}

deny[msg] {
	config := input.configuration.provider_config[_]
	config.name == "aws"
	region := config.expressions.region.constant_value
	region != ""
	not approved_regions[region]
	msg := sprintf("provider.aws: region '%s' is not in the approved region list %v", [region, approved_regions])
}
