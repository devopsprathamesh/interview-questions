#!/bin/bash
# Demonstrates the manifest-only vs. real-data Velero backup gap (Question 47).
set -euo pipefail

echo "=== Backup WITHOUT the CSI snapshot plugin (manifests only) ==="
velero backup create lab06-manifest-only-backup --include-namespaces default --snapshot-volumes=false
velero backup describe lab06-manifest-only-backup --details

echo ""
echo "=== Restore to confirm the volume comes back EMPTY ==="
velero restore create --from-backup lab06-manifest-only-backup
sleep 30
kubectl exec statefulset-with-data-0 -- ls /data   # expect: empty or missing testfile.txt

echo ""
echo "=== Backup WITH the CSI snapshot plugin (real data) ==="
velero backup create lab06-full-backup --include-namespaces default --snapshot-volumes=true
velero backup describe lab06-full-backup --details

echo ""
echo "=== Restore to confirm the volume comes back WITH real data ==="
velero restore create --from-backup lab06-full-backup
sleep 30
kubectl exec statefulset-with-data-0 -- cat /data/testfile.txt   # expect: lab06-test-data
