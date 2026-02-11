To push a UserDefinedNetwork (UDN) CR to a managed cluster from RHACM, use a ConfigurationPolicy that embeds the UDN YAML as raw YAML. RHACM replicates it automatically to the target cluster.

Policies enforce creation; ACM handles templating for per-cluster variabless like CIDR.

## Prerequisites

Managed cluster imported/joined to ACM hub (`oc get managedcluster <cluster-name>` shows "Ready").

Target namespace on managed cluster is `labeled k8s.ovn.org/primary-user-defined-network: ""` (required for UDN). Create via separate policy if needed.

Hub cluster has ACM Governance library installed.

## Steps
1. Create UDN YAML Snippet
Save as udn.yaml (Layer2 example):

```
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: my-udn
spec:
  type: Layer2
  nameservers:
    - 10.0.0.10
  subnets:
    - name: subnet1
      cidr: 10.128.0.0/24
      gateway: 10.128.0.1
```
Verify syntax: `oc create -f udn.yaml --dry-run=client -n <target-ns>`

2. Build ConfigurationPolicy
Create udn-policy.yaml on ACM hub:

```
apiVersion: policy.open-cluster-management.io/v1
kind: ConfigurationPolicy
metadata:
  name: deploy-udn
  namespace: default  # Hub namespace
spec:
  remediationAction: enforce  # Auto-creates UDN
  objectTemplates:
    - complianceType: musthave
      objectDefinition:
        apiVersion: k8s.ovn.org/v1
        kind: UserDefinedNetwork
        metadata:
          name: my-udn
          namespace: my-app-ns  # Target ns on managed cluster
        spec:  # Paste your UDN spec here
          type: Layer2
          # ... full spec from udn.yaml
  objectDefinitions: []  # Optional overrides
```

Apply the policy: `oc apply -f udn-policy.yaml`

3. Target the Managed Cluster
Link policy to cluster via PlacementRule (placement.yaml):

```
apiVersion: apps.open-cluster-management.io/v1
kind: PlacementRule
metadata:
  name: udn-placement
spec:
  clusterReplicas: 1
  clusterSelector:
    matchLabels:
      name: my-managed-cluster  # Label of target
```
Bind the policy: `oc apply -f placement.yaml`

Or use a policy wrapper (policy.yaml):

```
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: udn-policy
spec:
  remediationAction: enforce
  disabled: false
  policy-templates:
    - objectDefinition:
        apiVersion: policy.open-cluster-management.io/v1
        kind: ConfigurationPolicy
        # Embed full ConfigPolicy here
  placement:
    placementBindSelector:
      name: udn-binding
```
Apply both.

4. Verify Deployment
In the hub: `oc get policy udn-policy -o yaml` (status kust be "Compliant").

In the managed cluster: `oc get userdefinednetwork my-udn -n my-app-ns` (exists).

In the ACM console check: Governance > Policies > Filter by cluster (it must have a green check).
​
