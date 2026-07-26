output "workload_name" {
  value = random_pet.workload_name.id
}

output "report_path" {
  value = local_file.report.filename
}
