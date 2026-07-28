# Diagram 7: EBS/EFS CSI Volume Lifecycle

```mermaid
flowchart TD
    PVC[PersistentVolumeClaim created] --> SC{StorageClass}
    SC -->|EBS CSI driver| PROV1[Dynamic provisioning: create EBS volume in node's AZ]
    SC -->|EFS CSI driver| PROV2[Dynamic provisioning or existing EFS access point]
    PROV1 --> PV1[PersistentVolume - zonal, ReadWriteOnce]
    PROV2 --> PV2[PersistentVolume - multi-AZ, ReadWriteMany]
    PV1 --> ATTACH{Node in same AZ as volume?}
    ATTACH -->|yes| MOUNT[Volume attached and mounted to pod]
    ATTACH -->|no| STUCK[Pod stuck ContainerCreating - attach failure]
    PV2 --> MOUNTMANY[Mounted concurrently across nodes/AZs]

    DELETE[PVC deleted] --> RECLAIM{reclaimPolicy}
    RECLAIM -->|Delete| DESTROY[Underlying volume permanently destroyed]
    RECLAIM -->|Retain| ORPHAN[Volume orphaned - needs manual handling]
```

## Key points
- EBS volumes are zonal — a pod can only mount an EBS-backed PV if scheduled onto a node in the same AZ the volume lives in. This is a real scheduling constraint, not just a storage detail.
- EFS is multi-AZ and `ReadWriteMany` natively, at a different latency/cost profile than EBS.
- `reclaimPolicy: Delete` on a StorageClass backing important data with no separate backup is a silent data-loss trap — see [`docs/storage.md`](../docs/storage.md) §2–4.
