variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "manually_created_bucket_name" {
  type        = string
  description = "The exact name of the bucket you created manually via the AWS CLI in Step 1 - see README."
}
