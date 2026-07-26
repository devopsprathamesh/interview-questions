# Cheat Sheet: State Commands

| Command | Purpose | Risk / notes |
|---|---|---|
| `terraform state list` | Enumerate every resource address in state | First command when investigating "what does Terraform think it owns" |
| `terraform state show ADDR` | Dump a resource's recorded attributes | Compare against real cloud console when investigating drift |
| `terraform state mv SRC DST` | Relocate a state entry's address | Does not touch the real resource; used for refactors/renames — always follow with `terraform plan` to confirm zero diff |
| `terraform state mv -state-out=FILE SRC DST` | Move a resource into a *different* state file | The mechanism behind state splitting/merging |
| `terraform state rm ADDR` | Remove a resource from state without destroying it | Config must also be removed (or the next plan proposes a duplicate create) — prefer a `removed` block instead |
| `terraform state pull` | Print the current state to stdout | Use before any risky operation, to preserve a forensic copy |
| `terraform state push FILE` | Overwrite remote state with a local file | Bypasses lineage/serial checks — last resort only |
| `terraform import ADDR ID` | Legacy imperative import | Prefer `import` blocks (below) in modern Terraform |
| `terraform force-unlock LOCK_ID` | Remove a stale lock | Confirm the holder is dead first |

## Declarative alternatives (Terraform >= 1.5/1.7)

```hcl
# import block - reviewable in a plan before it's applied
import {
  to = aws_s3_bucket.data
  id = "my-existing-bucket-name"
}
```
```bash
terraform plan -generate-config-out=generated.tf   # drafts matching config for you
```

```hcl
# moved block - records a refactor declaratively, applies automatically for
# every consumer of a module without them running state mv themselves
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["web-01"]
}
```

```hcl
# removed block (Terraform >= 1.7) - reviewable decommission, state removal
# and config removal as one atomic change
removed {
  from = aws_instance.legacy_cache
  lifecycle {
    destroy = false   # state entry removed, cloud resource left untouched
  }
}
```

## Recovery quick reference
- **Corrupted state**: restore from backend version history (S3 versioning), never hand-edit JSON.
- **Deleted state**: infrastructure is untouched — rebuild via `import` blocks, foundational resources first.
- **Lineage mismatch on restore**: check `lineage` field before trusting a restored version; a serial-only check isn't sufficient.
- **Accidental `state rm`**: `terraform plan` will show a create — do not apply; `import` to restore the correct entry, or also remove the config if it was an intentional handoff.

See [Question 88-98 and category 2](../interview-questions/02-state-management.md) for the full scenarios behind each of these.
