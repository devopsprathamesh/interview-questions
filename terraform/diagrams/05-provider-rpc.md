# Diagram 5: Provider Communication (RPC)

Referenced from [`docs/terraform-internals.md`](../docs/terraform-internals.md#9-provider-rpc-communication).

```mermaid
sequenceDiagram
    participant Core as Terraform Core
    participant Plugin as Provider Plugin Process
    participant API as Cloud API (e.g. AWS)

    Core->>Plugin: Launch plugin binary (subprocess)
    Plugin-->>Core: Handshake (protocol version 5/6)
    Core->>Plugin: GetProviderSchema RPC
    Plugin-->>Core: Resource/data source schemas\n(types, computed, sensitive, ForceNew)
    Core->>Plugin: ValidateResourceConfig RPC
    Plugin-->>Core: Validation result
    Core->>Plugin: ReadResource RPC (refresh)
    Plugin->>API: Describe/Get calls
    API-->>Plugin: Current resource state
    Plugin-->>Core: Refreshed attributes
    Core->>Plugin: PlanResourceChange RPC
    Plugin-->>Core: Proposed new state + ForceNew markers
    Core->>Plugin: ApplyResourceChange RPC
    Plugin->>API: Create/Update/Delete calls
    API-->>Plugin: Result / error
    Plugin-->>Core: New resource state or error
    Core->>Plugin: Shutdown (on completion)
```

**Key points:**
- Terraform Core has no built-in knowledge of AWS, Kubernetes, or any specific API — everything resource-type-specific comes from the provider's schema, fetched once via RPC.
- A provider crash (segfault/panic) is a plugin process failure, diagnosed with `TF_LOG=trace`, not a Core bug — fixed with a provider version bump or upstream bug report.
- `PlanResourceChange` is where `ForceNew` (ties to §8 of `terraform-internals.md`, resource replacement) is determined per-attribute, per-provider-schema.
