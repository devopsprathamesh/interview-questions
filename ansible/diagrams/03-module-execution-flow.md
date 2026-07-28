# Diagram 3: Module Execution / Connection Plugin Flow

Referenced from [`docs/ansible-architecture.md`](../docs/ansible-architecture.md#2-connection-plugins).

```mermaid
sequenceDiagram
    participant Core as Ansible Core
    participant Conn as Connection Plugin (ssh)
    participant Host as Managed Host

    Core->>Conn: Establish connection (SSH, using ControlPersist if configured)
    Conn->>Host: Open session
    alt pipelining disabled (default)
        Core->>Conn: Transfer module code as a temp file
        Conn->>Host: Write temp file
        Core->>Conn: Execute: python /tmp/module.py args.json
        Conn->>Host: Run module
        Host-->>Conn: JSON result on stdout
        Conn->>Host: Clean up temp file
    else pipelining enabled
        Core->>Conn: Execute module code directly over the session\n(no temp file written)
        Conn->>Host: Run module inline
        Host-->>Conn: JSON result on stdout
    end
    Conn-->>Core: Return JSON result
    Core->>Core: Check changed/failed, trigger notify if applicable
```

**Key points:**
- Pipelining (`ansible.cfg`'s `[ssh_connection] pipelining = True`) skips the temp-file write/cleanup round-trip — a real speed win, but requires `requiretty` disabled in sudoers on the target.
- `become` inserts a privilege-escalation step (`sudo`, etc.) between the connection being established and the module actually executing — a become failure is a distinct failure mode from a connection failure, diagnosed differently (see [`docs/troubleshooting.md`](../docs/troubleshooting.md)).
