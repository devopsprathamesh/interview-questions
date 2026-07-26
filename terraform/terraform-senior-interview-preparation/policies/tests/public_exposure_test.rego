package main

test_denies_public_access_block_disabled {
	result := deny with input as {"resource_changes": [{
		"address": "aws_s3_bucket_public_access_block.bad",
		"type": "aws_s3_bucket_public_access_block",
		"change": {"after": {
			"block_public_acls": false,
			"restrict_public_buckets": true,
		}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "block_public_acls")
}

test_allows_public_access_block_enabled {
	result := deny with input as {"resource_changes": [{
		"address": "aws_s3_bucket_public_access_block.good",
		"type": "aws_s3_bucket_public_access_block",
		"change": {"after": {
			"block_public_acls": true,
			"restrict_public_buckets": true,
		}},
	}]}

	count(result) == 0
}

test_denies_database_port_open_to_world {
	result := deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.bad",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"after": {
			"cidr_ipv4": "0.0.0.0/0",
			"from_port": 5432,
		}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "5432")
}

test_allows_database_port_scoped_to_vpc {
	result := deny with input as {"resource_changes": [{
		"address": "aws_vpc_security_group_ingress_rule.good",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"after": {
			"cidr_ipv4": "10.0.0.0/16",
			"from_port": 5432,
		}},
	}]}

	count(result) == 0
}
