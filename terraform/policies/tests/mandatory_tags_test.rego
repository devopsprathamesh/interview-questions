package main

test_denies_missing_tags {
	result := deny with input as {"resource_changes": [{
		"address": "aws_instance.bad",
		"type": "aws_instance",
		"change": {"after": {"tags_all": {"Environment": "dev"}}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "ManagedBy")
}

test_allows_all_tags_present {
	result := deny with input as {"resource_changes": [{
		"address": "aws_instance.good",
		"type": "aws_instance",
		"change": {"after": {"tags_all": {"Environment": "dev", "ManagedBy": "terraform"}}},
	}]}

	count(result) == 0
}
