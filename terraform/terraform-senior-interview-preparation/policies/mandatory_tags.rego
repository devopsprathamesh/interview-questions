package main

# Denies any taggable resource missing a required tag.
# See interview-questions/13-governance.md Question 111.

required_tags := {"Environment", "ManagedBy"}

taggable_types := {
	"aws_instance", "aws_db_instance", "aws_s3_bucket", "aws_lb",
	"aws_vpc", "aws_security_group", "aws_eks_cluster",
}

deny[msg] {
	resource := input.resource_changes[_]
	taggable_types[resource.type]
	tags := object.get(resource.change.after, "tags_all", {})
	missing := required_tags - {k | tags[k]}
	count(missing) > 0
	msg := sprintf("%s: missing required tags: %v", [resource.address, missing])
}
