# Diagram 2: Pod Networking and VPC CNI ENI Allocation

```mermaid
flowchart TB
    subgraph Node["EC2 Node"]
        subgraph ENI1["Primary ENI"]
            IP1[Primary IP - node itself]
            IP2[Secondary IP - Pod A]
            IP3[Secondary IP - Pod B]
        end
        subgraph ENI2["Secondary ENI"]
            IP4[Secondary IP - Pod C]
            IP5[Secondary IP - Pod D]
        end
        IPAMD[ipamd daemon - manages warm IP/ENI pool]
        KUBELET[kubelet]
        IPAMD -.pre-allocates.-> ENI1
        IPAMD -.pre-allocates.-> ENI2
        KUBELET -->|requests IP for new pod| IPAMD
    end

    PODA[Pod A] --- IP2
    PODB[Pod B] --- IP3
    PODC[Pod C] --- IP4
    PODD[Pod D] --- IP5

    LIMIT[Instance-type ENI/IP limit reached] -.blocks.-> IPAMD
    PREFIX[Prefix Delegation: /28 prefix per ENI] -.increases capacity.-> ENI1
```

## Key points
- Every pod gets a real, routable VPC IP — a secondary IP on one of the node's attached ENIs, not an overlay-network address.
- `ipamd` maintains a "warm pool" of pre-allocated IPs/ENIs so pod scheduling doesn't block on live AWS API calls in the common case.
- Pod density per node is capped by the instance type's max ENIs × max IPs per ENI — a distinct scaling limit from CPU/memory.
- Prefix delegation assigns a `/28` block per ENI instead of individual IPs, raising the pods-per-node ceiling substantially — see [`docs/networking.md`](../docs/networking.md) §2–3.
