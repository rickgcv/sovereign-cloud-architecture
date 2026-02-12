#!/bin/bash
# Run when rollout is stuck and no pods exist. Paste output for diagnosis.
echo "=== All pods in namespace ==="
oc get pods
echo ""
echo "=== Deployment status ==="
oc get deployment sovereign-cloud-website -o wide
echo ""
echo "=== Newest ReplicaSet (full describe) ==="
oc describe replicaset -l app=sovereign-cloud-website | head -100
echo ""
echo "=== Deployment events ==="
oc get deployment sovereign-cloud-website -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
echo ""
echo ""
echo "=== Try to get pod creation failure (replicaset controller) ==="
RS=$(oc get rs -l app=sovereign-cloud-website --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
echo "Newest RS: $RS"
oc get rs "$RS" -o yaml 2>/dev/null | grep -A 20 "status:"
echo ""
echo "=== Done ==="
