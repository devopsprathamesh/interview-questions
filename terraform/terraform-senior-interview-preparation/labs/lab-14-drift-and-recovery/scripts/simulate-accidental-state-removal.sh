#!/usr/bin/env bash
# Simulates the "state rm without removing config" mistake from
# interview-questions/02-state-management.md Question 19: removes a resource's
# STATE ENTRY only (the real cloud resource is untouched), leaving the
# configuration still declaring it - proving the next apply would try to
# recreate it as a duplicate.
#
# Run this from inside a Lab 1 working directory that has already been applied.
set -euo pipefail

RESOURCE_ADDRESS="${1:-local_file.summary}"

echo "State BEFORE removal:"
terraform state list

echo ""
echo "Removing $RESOURCE_ADDRESS from state ONLY (the config still declares it,"
echo "and the real file/resource is untouched)..."
terraform state rm "$RESOURCE_ADDRESS"

echo ""
echo "State AFTER removal:"
terraform state list

echo ""
echo "Now run: terraform plan"
echo "Expect it to show $RESOURCE_ADDRESS as needing to be CREATED - because"
echo "config still declares it but state no longer has an entry. This is"
echo "exactly the duplicate-creation risk from interview-questions/02-state-management.md"
echo "Question 19. DO NOT apply this plan against a resource that still exists"
echo "and can't tolerate a duplicate (e.g., a uniquely-named cloud resource"
echo "would fail to create; a local_file would simply be overwritten)."
echo ""
echo "Recovery: either re-import the resource (terraform import '$RESOURCE_ADDRESS' <id>)"
echo "to restore the correct state entry, or - if this really was an intentional"
echo "hand-off - also remove the resource block from configuration (or use a"
echo "'removed' block) so config and state agree again."
