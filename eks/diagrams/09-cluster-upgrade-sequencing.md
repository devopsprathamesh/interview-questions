# Diagram 9: Cluster and Add-on Upgrade Sequencing

```mermaid
flowchart TD
    STEP0[Scan for deprecated/removed APIs<br/>pluto / kubent] --> STEP1
    STEP1[1. Upgrade control plane<br/>one minor version at a time] --> STEP2
    STEP2[2. Upgrade EKS-managed add-ons<br/>vpc-cni, coredns, kube-proxy, CSI drivers] --> STEP3
    STEP3[3. Upgrade self-managed add-ons<br/>Load Balancer Controller, Karpenter, ArgoCD<br/>check each project's compatibility matrix] --> STEP4
    STEP4[4. Upgrade node groups last<br/>new launch template/AMI, rolling drain+replace] --> DONE[Cluster fully upgraded]

    WRONG[Skipping straight to node upgrade<br/>before control plane/add-ons] -.common incident cause.-> STEP4
```

## Key points
- This order is not arbitrary: each step's compatibility assumptions depend on the previous step already being done — self-managed add-ons are checked against the *new* API version, which only exists after the control plane is upgraded.
- Node group upgrades are the actually disruptive step (existing pods get rescheduled) and should be paced conservatively, the same discipline as an ASG instance refresh.
- See [`docs/addons-and-upgrades.md`](../docs/addons-and-upgrades.md) §2 for the full reasoning.
