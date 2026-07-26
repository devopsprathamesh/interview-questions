package main

# Denies any S3 bucket public access block that leaves public access allowed,
# and any S3 bucket policy explicitly granting Principal = "*".
# See interview-questions/07-security.md Question 65 and docs/security.md §10.

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	after := resource.change.after
	not after.block_public_acls
	msg := sprintf("%s: block_public_acls must be true", [resource.address])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_public_access_block"
	after := resource.change.after
	not after.restrict_public_buckets
	msg := sprintf("%s: restrict_public_buckets must be true", [resource.address])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_policy"
	policy := json.unmarshal(resource.change.after.policy)
	statement := policy.Statement[_]
	statement.Effect == "Allow"
	statement.Principal == "*"
	msg := sprintf("%s: bucket policy grants public (Principal: *) access", [resource.address])
}

# Denies any security group rule opening a database-class port to 0.0.0.0/0.
# See interview-questions/07-security.md Question 65.

database_ports := {5432, 3306, 1433, 27017, 6379, 9200}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc_security_group_ingress_rule"
	after := resource.change.after
	after.cidr_ipv4 == "0.0.0.0/0"
	database_ports[after.from_port]
	msg := sprintf("%s: database port %d must not be open to 0.0.0.0/0", [resource.address, after.from_port])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_security_group"
	rule := resource.change.after.ingress[_]
	rule.cidr_blocks[_] == "0.0.0.0/0"
	database_ports[rule.from_port]
	msg := sprintf("%s: inline ingress rule opens database port %d to 0.0.0.0/0", [resource.address, rule.from_port])
}
