resource "random_pet" "workload_name" {
  length = 2
}

resource "local_file" "report" {
  filename = "${var.report_dir}/${random_pet.workload_name.id}.json"

  content = jsonencode({
    environment  = var.environment
    workload_name = random_pet.workload_name.id
  })
}
