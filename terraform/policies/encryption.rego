package main

# Denies unencrypted S3 buckets, RDS instances, and EBS volumes.
# See interview-questions/03-modules.md Question 33 and docs/security.md §6.

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_s3_bucket_server_side_encryption_configuration"
	rule := resource.change.after.rule[_]
	not rule.apply_server_side_encryption_by_default
	msg := sprintf("%s: S3 bucket must have server-side encryption configured", [resource.address])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	after := resource.change.after
	after.storage_encrypted == false
	msg := sprintf("%s: RDS instance must have storage_encrypted = true", [resource.address])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_db_instance"
	after := resource.change.after
	after.password != null
	msg := sprintf("%s: RDS instance must not use a hand-supplied password - use manage_master_user_password instead (see docs/security.md §1)", [resource.address])
}

deny[msg] {
	resource := input.resource_changes[_]
	resource.type == "aws_ebs_volume"
	after := resource.change.after
	after.encrypted == false
	msg := sprintf("%s: EBS volume must be encrypted", [resource.address])
}
