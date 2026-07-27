# Diagram 13: AWX / Ansible Automation Platform Architecture

Referenced from [`docs/ansible-architecture.md` §7](../docs/ansible-architecture.md#7-awx--ansible-automation-platform-architecture) and [`docs/ha-dr.md`](../docs/ha-dr.md).

```mermaid
flowchart TD
    User["Engineer / on-call\n(via UI, API, or webhook)"] --> JobTemplate["Job Template\n(playbook + inventory +\ncredentials + extra vars)"]
    JobTemplate --> RBAC{RBAC check:\nallowed to launch this template?}
    RBAC -->|denied| Deny[Launch denied]
    RBAC -->|allowed| CredInjection["Credential injected into job\n(never exposed to the launcher)"]
    CredInjection --> EE["Execution Environment\n(pinned container image)"]
    EE --> ExecutionNode["Execution node runs\nansible-playbook"]
    ExecutionNode --> Targets[Managed hosts]
    ExecutionNode --> JobHistory[(Job history + logs\nin PostgreSQL - HA'd)]

    subgraph Cluster["AWX/Automation Platform Cluster"]
        ControlNode1[Control node 1]
        ControlNode2[Control node 2]
        ExecutionNode
        JobHistory
    end
```

**Key points:**
- Credentials are injected into a job's execution scope without ever being exposed to the person who launched it — access to *launch* a template using a credential is separate from access to *view* the credential's value.
- Every job runs inside a specific, pinned Execution Environment image — not whatever happens to be installed on a shared control node.
- The PostgreSQL backend (job history, credentials, inventory data) is the most critical piece to protect for HA — see [`docs/ha-dr.md` §1](../docs/ha-dr.md#1-control-plane-ha-awx--ansible-automation-platform).
