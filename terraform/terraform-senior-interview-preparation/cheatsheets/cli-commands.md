# Cheat Sheet: Terraform CLI Commands

| Command | Purpose | Notes |
|---|---|---|
| `terraform init` | Download providers/modules, configure backend | Run `-upgrade` deliberately, never incidentally |
| `terraform init -backend-config=<file>` | Init with a partial backend config (bucket/key/region from a file, not hardcoded) | Standard pattern for reusable configs across environments |
| `terraform init -migrate-state` | Migrate state to a new/changed backend | Back up state first; do during a change window |
| `terraform fmt -check -recursive` | Verify canonical formatting without modifying files | CI-friendly; `terraform fmt` alone rewrites files |
| `terraform validate` | Check internal config consistency | No provider API calls; does not catch drift or invalid IDs |
| `terraform plan` | Compute and show the diff | Always read the reasons for any `-/+` (replace) |
| `terraform plan -out=FILE` | Save the plan for later, guaranteed-identical apply | Pair with `terraform apply FILE`, never re-plan at apply time |
| `terraform plan -detailed-exitcode` | 0=no changes, 1=error, 2=changes present | The mechanism behind automated drift detection |
| `terraform plan -destroy` | Preview a destroy without applying it | Safer than jumping straight to `destroy` |
| `terraform plan -replace=ADDR` | Explicitly plan a replacement for one resource | Modern replacement for the deprecated `taint` command |
| `terraform plan -target=ADDR` | Narrow the plan to one resource + its dependencies | Emergency use only — see [Question 106](../interview-questions/12-performance-scale.md#question-106-the--target-habit-nobody-wanted-to-break) |
| `terraform apply` | Apply a fresh plan (prompts for confirmation) | |
| `terraform apply FILE` | Apply an exact saved plan | The correct CI/CD pattern |
| `terraform apply -auto-approve` | Apply without interactive confirmation | CI only, never local interactive use |
| `terraform destroy` | Destroy everything in the configuration | Always `plan -destroy` first for anything non-trivial |
| `terraform graph` | Render the dependency graph (DOT format) | Pipe to `dot -Tsvg` for a visual |
| `terraform console` | Interactive expression evaluator against current state | Great for testing a `for` expression before committing it |
| `terraform force-unlock LOCK_ID` | Remove a stale state lock | Confirm the holder is genuinely dead first — never routine |
| `terraform providers` | List required providers | |
| `terraform providers lock -platform=X` | Add checksums for a platform to the lock file | Needed when your team uses mixed OS/architectures |
| `terraform test` | Run native test suites (`.tftest.hcl`) | See the [Testing cheat sheet](testing.md) |
| `terraform show -json FILE` | Render a saved plan as JSON | Input for policy-as-code (Conftest/OPA) |
| `terraform output` | Show root module outputs | `-json` for machine consumption, `-raw` for a single scalar value |
| `TF_LOG=debug terraform plan` | Verbose logging for troubleshooting | Also `TF_LOG=trace` for provider RPC detail |

## Exit codes
- `0`: success, no error
- `1`: error
- `2`: (with `-detailed-exitcode` on `plan`) success, changes present
