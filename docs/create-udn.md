# Create a User Defined Network (UDN) for Tenant and Network Separation

Push a User Defined Network (UDN) to a managed cluster from RHACM using a ConfigurationPolicy. RHACM replicates the UDN to the target cluster so you can enforce **network isolation** between tenants or workloads on a shared platform.

**What UDN provides:** UDN gives **logical (L2/L3) network separation** within a cluster: namespaces attached to different UDNs cannot reach each other by default, which is how you isolate tenants in an MSP shared platform. When the underlying infrastructure uses separate VLANs or a **Localnet** topology, that isolation can extend to **physical network separation** (different VLANs/segments). This doc focuses on creating the UDN via RHACM; for physical underlay, combine with [Localnet](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/multiple_networks/primary-networks#nw-cudn-localnet_user-defined-networks) and VLAN design on your nodes.

Policies enforce creation; ACM can drive per-cluster variables (e.g. CIDR) via policy templating.

## Prerequisites

- Managed cluster imported/joined to the ACM hub (`oc get managedcluster <cluster-name>` shows "Ready").
- Target namespace on the managed cluster **has** the label `k8s.ovn.org/primary-user-defined-network: ""` (required for primary UDN). This label can only be set when the namespace is created; create the namespace with this label first (e.g. via a separate policy), then create the UDN before any pods.
- Hub cluster has the ACM Governance (policy) components installed.

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

Or use a policy wrapper (policy.yaml) and bind it to a placement with a **PlacementBinding**:

**policy.yaml** (Policy + ConfigurationPolicy template):

```
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: udn-policy
  namespace: default
spec:
  remediationAction: enforce
  disabled: false
  policy-templates:
    - objectDefinition:
        apiVersion: policy.open-cluster-management.io/v1
        kind: ConfigurationPolicy
        metadata:
          name: deploy-udn
        spec:
          remediationAction: enforce
          objectTemplates:
            - complianceType: musthave
              objectDefinition:
                apiVersion: k8s.ovn.org/v1
                kind: UserDefinedNetwork
                metadata:
                  name: my-udn
                  namespace: my-app-ns
                spec:
                  type: Layer2
                  nameservers: ["10.0.0.10"]
                  subnets:
                    - name: subnet1
                      cidr: 10.128.0.0/24
                      gateway: 10.128.0.1
```

**placement-binding.yaml** (required to send the policy to clusters selected by the PlacementRule):

```
apiVersion: policy.open-cluster-management.io/v1
kind: PlacementBinding
metadata:
  name: udn-binding
  namespace: default
placementRef:
  apiGroup: apps.open-cluster-management.io
  kind: PlacementRule
  name: udn-placement
subjects:
  - apiGroup: policy.open-cluster-management.io
    kind: Policy
    name: udn-policy
```

Apply Policy, PlacementRule, and PlacementBinding: `oc apply -f policy.yaml -f placement.yaml -f placement-binding.yaml`

4. Verify Deployment
In the hub: `oc get policy udn-policy -o yaml` (status must be "Compliant").

In the managed cluster: `oc get userdefinednetwork my-udn -n my-app-ns` (exists).

In the ACM console check: Governance > Policies > Filter by cluster (it must have a green check).
​
