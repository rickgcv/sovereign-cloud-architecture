#!/bin/bash
# Run this on your machine (where oc is installed and you're logged in).
# Paste the output so we can diagnose ImagePullBackOff / build / image issues.
# Usage: ./check-cluster.sh   or   bash openshift/check-cluster.sh

# Don't use set -e so we get full output even when some resources are missing
echo "=== Project ==="
oc project 2>/dev/null || true
echo ""

echo "=== Builds (last 5) ==="
oc get builds -l app=sovereign-cloud-website 2>/dev/null | tail -5
echo ""

echo "=== Latest build status (if any) ==="
oc get build -l app=sovereign-cloud-website --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -1
BUILD=$(oc get build -l app=sovereign-cloud-website -o name 2>/dev/null | tail -1)
if [ -n "$BUILD" ]; then
  echo "Build details:"
  oc get $BUILD -o jsonpath='  Phase: {.status.phase}, Reason: {.status.reason}{"\n"}' 2>/dev/null
  oc get $BUILD -o jsonpath='  Output: {.status.output.to.imageDigest}{"\n"}' 2>/dev/null
fi
echo ""

echo "=== ImageStream sovereign-cloud-website ==="
oc get is sovereign-cloud-website 2>/dev/null || echo "(not found)"
echo ""

echo "=== ImageStreamTag sovereign-cloud-website:latest ==="
oc get istag sovereign-cloud-website:latest 2>/dev/null || echo "(not found)"
echo ""

echo "=== Image pull spec (if ImageStreamTag exists) ==="
oc get istag sovereign-cloud-website:latest -o jsonpath='{.image.dockerImageReference}' 2>/dev/null || echo "(none)"
echo ""
echo ""

echo "=== Deployment image field ==="
oc get deployment sovereign-cloud-website -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "(deployment not found)"
echo ""
echo ""

echo "=== Pods (sovereign-cloud-website) ==="
oc get pods -l app=sovereign-cloud-website 2>/dev/null
echo ""

echo "=== Pod describe (if any pod exists) ==="
POD=$(oc get pods -l app=sovereign-cloud-website -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then oc describe pod "$POD" 2>/dev/null; else echo "(no pods)"; fi
echo ""

echo "=== ReplicaSets (for rollout) ==="
oc get replicaset -l app=sovereign-cloud-website 2>/dev/null
echo ""

echo "=== Done ==="
