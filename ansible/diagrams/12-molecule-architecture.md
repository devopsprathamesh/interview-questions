# Diagram 12: Molecule Testing Architecture

Referenced from [`docs/testing.md`](../docs/testing.md) and [Lab 11](../labs/lab-11-molecule-testing/).

```mermaid
flowchart TD
    MoleculeTest["molecule test"] --> Create["create:\nstart Docker/Podman container(s)\nper molecule.yml platforms"]
    Create --> Converge["converge:\nrun converge.yml\n(applies the role under test)"]
    Converge --> Idempotence["idempotence:\nrun converge.yml AGAIN"]
    Idempotence --> IdemCheck{Any changed\ntasks on 2nd run?}
    IdemCheck -->|yes| Fail["FAIL - role is not idempotent"]
    IdemCheck -->|no| Verify["verify:\nrun verify.yml assertions\nagainst real resulting state"]
    Verify --> VerifyCheck{Assertions pass?}
    VerifyCheck -->|no| Fail2["FAIL - state doesn't match\nintended outcome"]
    VerifyCheck -->|yes| Destroy["destroy:\ntear down container(s)"]
    Destroy --> Pass["PASS"]
```

**Key points:**
- The `idempotence` stage is Molecule's automated, enforced proof of the idempotency contract — not an assumption, a real test that fails the build if a second run reports any changes.
- `verify.yml` checks the **actual observable state** (a running service, correct config content) — passing `converge` alone only proves "Ansible didn't error," not "the intended outcome is true."
- Using Docker/Podman as the driver means this entire cycle is free and fast (seconds), suitable for every PR — real-cloud integration testing is a separate, costlier tier (see [`docs/testing.md` §6](../docs/testing.md#6-mocking-cloud-calls-for-fast-free-unit-level-testing)).
