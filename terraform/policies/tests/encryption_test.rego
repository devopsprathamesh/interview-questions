package main

test_denies_unencrypted_rds {
	result := deny with input as {"resource_changes": [{
		"address": "aws_db_instance.bad",
		"type": "aws_db_instance",
		"change": {"after": {"storage_encrypted": false, "password": null}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "storage_encrypted")
}

test_allows_encrypted_rds {
	result := deny with input as {"resource_changes": [{
		"address": "aws_db_instance.good",
		"type": "aws_db_instance",
		"change": {"after": {"storage_encrypted": true, "password": null}},
	}]}

	count(result) == 0
}

test_denies_hardcoded_rds_password {
	result := deny with input as {"resource_changes": [{
		"address": "aws_db_instance.bad",
		"type": "aws_db_instance",
		"change": {"after": {"storage_encrypted": true, "password": "hardcoded123"}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "manage_master_user_password")
}

test_denies_unencrypted_ebs {
	result := deny with input as {"resource_changes": [{
		"address": "aws_ebs_volume.bad",
		"type": "aws_ebs_volume",
		"change": {"after": {"encrypted": false}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "encrypted")
}
