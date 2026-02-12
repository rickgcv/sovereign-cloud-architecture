# Deploy Red Hat Advanced Cluster Management (RHACM)

This guide provides step-by-step instructions for deploying Red Hat Advanced Cluster Management (RHACM) on your management cluster.

## Prerequisites

- Red Hat OpenShift Platform Plus cluster (version 4.12 or later) with cluster-admin permissions
- Access to the Red Hat Container Registry or a disconnected registry with RHACM images
- At least 16GB of RAM and 4 CPU cores available for RHACM components
- Sufficient storage for RHACM operator and hub components
- Network connectivity to managed clusters (if deploying in connected mode)

## Step 1: Create the RHACM Namespace

Create a dedicated namespace for RHACM:

```bash
oc create namespace open-cluster-management
```

Verify the namespace was created:

```bash
oc get namespace open-cluster-management
```

## Step 2: Create OperatorGroup

Create an OperatorGroup to define the scope of the RHACM operator:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: open-cluster-management
  namespace: open-cluster-management
spec:
  targetNamespaces:
  - open-cluster-management
EOF
```

## Step 3: Create Subscription for RHACM Operator

Subscribe to the RHACM operator from the Red Hat Operator Catalog:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.15
  installPlanApproval: Automatic
  name: advanced-cluster-management
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

**Note:** Adjust the `channel` value based on your RHACM version requirements. Common channels include:
- `release-2.15` (latest stable)
- `release-2.14`
- `release-2.13`

## Step 4: Wait for Operator Installation

Monitor the operator installation:

```bash
oc get csv -n open-cluster-management
```

Wait until the operator shows `PHASE: Succeeded`:

```bash
oc wait --for=condition=Installed csv/advanced-cluster-management.v2.15.0 -n open-cluster-management --timeout=600s
```

**Note:** Replace `v2.15.0` with your specific RHACM version.

## Step 5: Create MultiClusterHub Instance

Create the MultiClusterHub (MCH) custom resource to deploy RHACM:

```bash
cat <<EOF | oc apply -f -
apiVersion: operator.open-cluster-management.io/v1
kind: MultiClusterHub
metadata:
  name: multiclusterhub
  namespace: open-cluster-management
spec:
  imagePullSecret: ""
  disableHubSelfManagement: false
  availabilityConfig: HighAvailability
EOF
```

**Configuration options:**
- `imagePullSecret`: Specify if using a private registry
- `disableHubSelfManagement`: Set to `true` to prevent RHACM from managing itself
- `availabilityConfig`: Options are `HighAvailability` or `Basic`

## Step 6: Monitor MultiClusterHub Deployment

Watch the MCH deployment progress:

```bash
oc get multiclusterhub -n open-cluster-management -w
```

Check the status:

```bash
oc get multiclusterhub multiclusterhub -n open-cluster-management -o jsonpath='{.status.phase}'
```

Wait until the status shows `Running` (this may take 10-15 minutes):

```bash
oc wait --for=condition=Available multiclusterhub/multiclusterhub -n open-cluster-management --timeout=1800s
```

## Step 7: Verify Component Installation

Verify that all RHACM components are running:

```bash
oc get pods -n open-cluster-management
```

Expected pods should be in `Running` or `Completed` state:
- `multiclusterhub-repo-*`
- `multiclusterhub-operator-*`
- `multicluster-operators-*`
- `ocm-controller-*`
- `ocm-webhook-*`
- `search-*`
- `management-ingress-*`

## Step 8: Access the RHACM Console

Get the console URL:

```bash
oc get route multicloud-console -n open-cluster-management -o jsonpath='{.spec.host}'
```

Or retrieve the full console information:

```bash
oc get route multicloud-console -n open-cluster-management
```

Access the console using the route URL. The default credentials can be retrieved:

```bash
oc get secret multiclusterhub-console-config -n open-cluster-management -o jsonpath='{.data.username}' | base64 -d
echo
oc get secret multiclusterhub-console-config -n open-cluster-management -o jsonpath='{.data.password}' | base64 -d
echo
```

## Step 9: Verify API Access

Test RHACM API access:

```bash
oc api-resources | grep -i "cluster"
```

You should see resources like:
- `managedclusters`
- `klusterlets`
- `clusterclaims`
- `clusterdeployments`

## Step 10: (Optional) Configure for Disconnected Environment

If deploying in a disconnected environment, configure image pull secrets:

```bash
# Create pull secret for your registry
oc create secret docker-registry acm-pull-secret \
  --docker-server=<your-registry-url> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n open-cluster-management

# Update MultiClusterHub to use the secret
oc patch multiclusterhub multiclusterhub -n open-cluster-management \
  --type merge -p '{"spec":{"imagePullSecret":"acm-pull-secret"}}'
```

## Verification Checklist

- [ ] RHACM operator is installed and running
- [ ] MultiClusterHub status is `Running`
- [ ] All RHACM pods are in `Running` state
- [ ] Console route is accessible
- [ ] API resources are available
- [ ] Can access RHACM console with credentials

## Troubleshooting

### Check operator logs:

```bash
oc logs -n open-cluster-management deployment/multiclusterhub-operator
```

### Check MultiClusterHub events:

```bash
oc describe multiclusterhub multiclusterhub -n open-cluster-management
```

### Check pod status and logs:

```bash
oc get pods -n open-cluster-management
oc logs <pod-name> -n open-cluster-management
```

### Common issues:

1. **Image pull errors**: Verify registry access and image pull secrets
2. **Insufficient resources**: Check cluster node capacity
3. **Network issues**: Verify network policies allow RHACM component communication

## Next Steps

After successful deployment:

1. Import or create managed clusters
2. Configure cluster policies and governance
3. Set up GitOps for cluster management
4. Configure observability and monitoring

For more information on managing clusters with RHACM, refer to the [RHACM documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/).

