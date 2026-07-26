resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # Rules are managed as standalone resources below, not inline, so adding or
  # removing a single rule never produces a diff touching any other rule -
  # see docs/terraform-internals.md and interview-questions/01-terraform-core.md Question 2.
  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id = aws_security_group.this.id
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks[0] : null

  description = each.key

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id = aws_security_group.this.id
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks[0] : null

  description = each.key

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}
