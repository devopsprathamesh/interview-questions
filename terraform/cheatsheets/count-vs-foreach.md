# Cheat Sheet: `count` vs `for_each`

| | `count` | `for_each` |
|---|---|---|
| Identity | Positional index (`[0]`, `[1]`, ...) | Map key or set member (`["web-01"]`) |
| Removing an item from the middle | **Shifts every subsequent index** → cascading destroy/recreate | Only the removed key's resource is affected |
| Input type | Number | Map or set of strings |
| Reference inside the block | `count.index` | `each.key`, `each.value` |
| Right use case | The 0/1 conditional-resource idiom; truly fixed-cardinality, order-independent sets | Any collection whose membership can change over time |

## The failure this table exists to prevent
Removing the first item from a `count`-driven list of 6 subnets doesn't destroy just that one — every subsequent index's *meaning* shifts while its *identity* (the index) stays the same, so Terraform sees 5 resources needing replacement, not 1. See [Question 1](../interview-questions/01-terraform-core.md#question-1-the-subnet-that-shifted).

## Default rule of thumb
**Default to `for_each`** for anything where membership can change. Reserve `count` for:
```hcl
resource "aws_instance" "optional" {
  count = var.enable_feature ? 1 : 0   # the 0/1 idiom - the one place count is still preferred
}
```

## Migrating `count` → `for_each` without recreation
```hcl
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["web-01"]
}
# ...repeat for every existing index...
```
Then change the resource block to `for_each`, verify `terraform plan` shows **zero changes**. See [Question 9](../interview-questions/01-terraform-core.md#question-9-converting-a-legacy-count-fleet-to-for_each-without-downtime) and [Lab 7](../labs/lab-07-refactoring-state/).
