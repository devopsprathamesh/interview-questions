package main

# Denies oversized instance types outside production.
# See interview-questions/13-governance.md Question 112.

max_instance_size := {
	"dev": {"t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "m5.large", "m5.xlarge"},
	"staging": {"t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"},
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_instance"
	after := resource.change.after
	env := object.get(after.tags_all, "Environment", "")
	allowed := max_instance_size[env]
	allowed
	not allowed[after.instance_type]
	not object.get(after.tags_all, "SizeExceptionTicket", false)
	msg := sprintf("%s: instance_type %s exceeds the allowed size for the %s environment (add a SizeExceptionTicket tag for a reviewed, time-bound exception - see interview-questions/13-governance.md Question 112)", [resource.address, after.instance_type, env])
}
