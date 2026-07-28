package main

test_denies_oversized_dev_instance {
	result := deny with input as {"resource_changes": [{
		"address": "aws_instance.bad",
		"type": "aws_instance",
		"change": {"after": {
			"instance_type": "m5.24xlarge",
			"tags_all": {"Environment": "dev"},
		}},
	}]}

	count(result) > 0
	some msg in result
	contains(msg, "m5.24xlarge")
}

test_allows_normal_dev_instance {
	result := deny with input as {"resource_changes": [{
		"address": "aws_instance.good",
		"type": "aws_instance",
		"change": {"after": {
			"instance_type": "t3.medium",
			"tags_all": {"Environment": "dev"},
		}},
	}]}

	count(result) == 0
}

test_allows_oversized_instance_with_exception_ticket {
	result := deny with input as {"resource_changes": [{
		"address": "aws_instance.exception",
		"type": "aws_instance",
		"change": {"after": {
			"instance_type": "m5.24xlarge",
			"tags_all": {"Environment": "dev", "SizeExceptionTicket": "PERF-1102"},
		}},
	}]}

	count(result) == 0
}
