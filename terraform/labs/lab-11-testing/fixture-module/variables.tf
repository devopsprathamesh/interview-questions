variable "environment" {
  type        = string
  description = "Environment name. Deliberately validated with a regex that has a planted bug for the mutation-testing exercise - see README."

  validation {
    # NOTE: this condition is intentionally correct as shipped. The lab's
    # mutation-testing exercise has you temporarily introduce a bug here
    # yourself and observe which test catches it - see README Step 4.
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "report_dir" {
  type        = string
  description = "Directory to write the generated report file into."
  default     = "./output"
}
