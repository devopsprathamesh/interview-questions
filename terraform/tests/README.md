# tests/

This top-level directory is reserved for organization-wide test suites spanning multiple modules. It's intentionally empty as of this repository's initial build — every test suite produced so far is scoped correctly to what it tests, not centralized here:

- Module-level `terraform test` suites live next to the module they test: [`modules/vpc/tests/`](../modules/vpc/tests/), [`modules/security-groups/tests/`](../modules/security-groups/tests/).
- The zero-cost testing-pattern demonstration lives in [`labs/lab-11-testing/fixture-module/tests/`](../labs/lab-11-testing/fixture-module/tests/).
- Policy tests (`opa test` fixtures for the Rego rules in `policies/`) live in [`policies/tests/`](../policies/tests/), next to the policies they test.

If you add a genuinely cross-cutting test (e.g., an end-to-end test spanning multiple modules composed together, distinct from any single module's own unit tests), this is where it belongs.
