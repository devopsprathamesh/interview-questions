locals {
  az_count = length(var.availability_zones)

  # Split the VPC CIDR into /24s (assuming a /16 input; works for other sizes too,
  # just changes the resulting subnet size proportionally): first half for public,
  # second half for private, indexed by AZ position within each half.
  public_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.cidr_block, 8, idx)
  }

  private_subnet_cidrs = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.cidr_block, 8, idx + local.az_count)
  }

  # Determines which AZ(s) actually get a NAT gateway based on the chosen strategy.
  nat_gateway_azs = var.nat_strategy == "per_az" ? toset(var.availability_zones) : (
    var.nat_strategy == "single" ? toset([var.availability_zones[0]]) : toset([])
  )

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "vpc"
  })
}
