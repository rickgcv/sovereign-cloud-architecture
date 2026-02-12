# Install and Configure Workload Identity Manager (Zero Trust)

This guide walks through installing and configuring **Red Hat Zero Trust Workload Identity Manager** on OpenShift Container Platform. It provides cryptographically verifiable workload identities (SPIFFE/SPIRE) and supports the sovereign cloud’s zero-trust security model.

## Overview

The Zero Trust Workload Identity Manager is an OpenShift Operator that manages:

- **SPIRE Server** – Issues and manages SPIFFE identities in a trust domain
- **SPIRE Agent** – Runs on nodes, performs workload attestation, and delivers SVIDs to pods
- **SPIFFE CSI Driver** – Mounts the Workload API into pods so they can obtain SVIDs
- **SPIRE OIDC Discovery Provider** – Exposes SPIRE identities for OIDC-compliant systems

Workloads get short-lived, verifiable identities (X.509 or JWT) instead of long-lived secrets, improving security and auditability.

## Prerequisites

- OpenShift Container Platform **4.20 or later** (4.18–4.19 supported as Technology Preview; 4.20+ for GA).
- **cluster-admin** access.
- At least **1 Gi** of persistent storage available for the SPIRE Server (default uses a PVC).
- Operator installation is **not** allowed in `openshift-*` or `default`; use a **custom namespace**.

## Step 1: Create a Custom Namespace

Use a dedicated namespace for the operator and all operands:

```bash
oc create namespace workload-identity-manager
```

Verify:

```bash
oc get namespace workload-identity-manager
```

## Step 2: Create OperatorGroup and Subscription

Create an OperatorGroup and subscribe to the Zero Trust Workload Identity Manager operator:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: workload-identity-manager-operatorgroup
  namespace: workload-identity-manager
spec:
  targetNamespaces:
  - workload-identity-manager
EOF
```

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: zero-trust-workload-identity-manager
  namespace: workload-identity-manager
spec:
  channel: stable
  installPlanApproval: Automatic
  name: zero-trust-workload-identity-manager
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

**Note:** If the package name differs in your catalog, search with `oc get packagemanifests -n openshift-marketplace | grep -i workload` and use the correct `name` in the Subscription.

## Step 3: Wait for the Operator to Be Ready

List cluster service versions and wait until the operator is installed:

```bash
oc get csv -n workload-identity-manager
```

Wait for the Zero Trust Workload Identity Manager CSV to show `PHASE: Succeeded`:

```bash
oc wait --for=condition=Installed csv/zero-trust-workload-identity-manager.v1.0.0 -n workload-identity-manager --timeout=600s
```

Replace `v1.0.0` with the version reported by `oc get csv -n workload-identity-manager`.

## Step 4: Create the SPIRE Server (CR named `cluster`)

All operand CRs must be named **`cluster`** (singleton per cluster). Create the SPIRE Server first; it needs a trust domain, cluster name, and persistence.

Set variables for your environment:

```bash
export TRUST_DOMAIN=example.org
export CLUSTER_NAME=my-cluster
export ZTWIM_NS=workload-identity-manager
```

Create the `SpireServer` custom resource. The API group may be `ztwim.openshift.io` or `spire.ztwim.openshift.io` depending on version; run `oc get crd | grep -i spire` to confirm:

```bash
cat <<EOF | oc apply -f -
apiVersion: ztwim.openshift.io/v1alpha1
kind: SpireServer
metadata:
  name: cluster
  namespace: ${ZTWIM_NS}
spec:
  trustDomain: ${TRUST_DOMAIN}
  clusterName: ${CLUSTER_NAME}
  jwtIssuer: https://oidc-discovery-provider-${ZTWIM_NS}.apps.$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
  persistence:
    size: 1Gi
    storageClassName: ""   # use cluster default if empty
EOF
```

**Notes:**

- `jwtIssuer` must be a **valid URL** (required by the API). Use your OIDC discovery provider URL; the operator may create a route like `oidc-discovery-provider-<namespace>.apps.<cluster-domain>`.
- For production, consider PostgreSQL persistence and HA; see [Red Hat documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/zero-trust-workload-identity-manager).

Wait for the SPIRE Server to be ready:

```bash
oc get spireserver -n ${ZTWIM_NS}
oc get pods -n ${ZTWIM_NS} -l app.kubernetes.io/name=spire-server
```

## Step 5: Create the SPIRE Agent (CR named `cluster`)

The SPIRE Agent runs on nodes and performs node and workload attestation. Create a `SpireAgent` named `cluster`:

```bash
cat <<EOF | oc apply -f -
apiVersion: ztwim.openshift.io/v1alpha1
kind: SpireAgent
metadata:
  name: cluster
  namespace: ${ZTWIM_NS}
spec:
  trustDomain: ${TRUST_DOMAIN}
  clusterName: ${CLUSTER_NAME}
  spireServerAddress: spire-server.${ZTWIM_NS}.svc
  spireServerPort: 8081
EOF
```

The agent will be deployed as a DaemonSet. Verify:

```bash
oc get spireagent -n ${ZTWIM_NS}
oc get daemonset -n ${ZTWIM_NS}
```

## Step 6: Create the SPIFFE CSI Driver (CR named `cluster`)

The CSI driver mounts the Workload API into pods so they can obtain SVIDs. Ensure `agentSocketPath` matches the path used by the SPIRE Agent (defaults are usually aligned when both use operator defaults).

```bash
cat <<EOF | oc apply -f -
apiVersion: ztwim.openshift.io/v1alpha1
kind: SpiffeCSIDriver
metadata:
  name: cluster
  namespace: ${ZTWIM_NS}
spec:
  trustDomain: ${TRUST_DOMAIN}
  clusterName: ${CLUSTER_NAME}
  # agentSocketPath must match SpireAgent.spec.socketPath if you customize it
EOF
```

Verify:

```bash
oc get spiffecsidriver -n ${ZTWIM_NS}
```

## Step 7: Create the SPIRE OIDC Discovery Provider (CR named `cluster`)

The OIDC Discovery Provider exposes SPIRE-issued JWTs for OIDC-compliant systems. Create a `SpireOIDCDiscoveryProvider` named `cluster`:

```bash
cat <<EOF | oc apply -f -
apiVersion: ztwim.openshift.io/v1alpha1
kind: SpireOIDCDiscoveryProvider
metadata:
  name: cluster
  namespace: ${ZTWIM_NS}
spec:
  trustDomain: ${TRUST_DOMAIN}
  clusterName: ${CLUSTER_NAME}
  jwtIssuer: https://oidc-discovery-provider-${ZTWIM_NS}.apps.$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
  managedRoute: true
EOF
```

Use the same `jwtIssuer` value as in `SpireServer` so tokens are consistent. The operator can create and manage the Route when `managedRoute: true`.

Verify:

```bash
oc get spireoidcdiscoveryprovider -n ${ZTWIM_NS}
oc get route -n ${ZTWIM_NS}
```

## Step 8: (Optional) Create ZeroTrustWorkloadIdentityManager CR

Some versions use an umbrella CR `ZeroTrustWorkloadIdentityManager` named `cluster` to aggregate status. If your operator exposes it, create it:

```bash
cat <<EOF | oc apply -f -
apiVersion: ztwim.openshift.io/v1alpha1
kind: ZeroTrustWorkloadIdentityManager
metadata:
  name: cluster
  namespace: ${ZTWIM_NS}
spec: {}
EOF
```

Check operator documentation for your version; the four operand CRs (SpireServer, SpireAgent, SpiffeCSIDriver, SpireOIDCDiscoveryProvider) may be sufficient.

## Step 9: Register Workloads and Consume SVIDs

After the stack is running, workloads must be **registered** with SPIRE (via registration entries or the SPIRE Controller Manager CRDs) and then can request SVIDs.

1. **Use the SPIFFE CSI volume in a pod** so the workload can call the Workload API:

   ```yaml
   spec:
     containers:
     - name: app
       volumeMounts:
       - name: spiffe-workload-api
         mountPath: /run/spire/sockets
     volumes:
     - name: spiffe-workload-api
       csi:
         driver: csi.spiffe.io
         volumeAttributes:
           spiffe.io/trust-domain: "example.org"
   ```

2. **Register the workload** with the SPIRE Server (e.g. via ClusterSPIFFEID or equivalent CRD that your operator provides, or manual registration entries). The registration defines the selectors (e.g. pod label, namespace) that determine which SPIFFE ID is issued.

3. **Obtain SVIDs** from the Workload API inside the pod (e.g. using the SPIFFE SDK or a sidecar that writes certs to a file).

See [SPIFFE documentation](https://spiffe.io/docs/latest/deploying/registering/) and the Red Hat [Zero Trust Workload Identity Manager](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/zero-trust-workload-identity-manager) guide for workload registration and integration details.

## Verification Checklist

- [ ] Operator CSV is `Succeeded` in `workload-identity-manager`.
- [ ] `SpireServer` pod is running (StatefulSet).
- [ ] `SpireAgent` DaemonSet has running pods on worker nodes.
- [ ] `SpiffeCSIDriver` is installed; pods can use the CSI volume.
- [ ] `SpireOIDCDiscoveryProvider` is running and Route is created (if `managedRoute: true`).
- [ ] `jwtIssuer` is a valid URL and matches in SpireServer and SpireOIDCDiscoveryProvider.
- [ ] Workloads can mount the SPIFFE CSI volume and receive SVIDs after registration.

## Troubleshooting

- **Operator not found in catalog:** Confirm OpenShift version (4.20+ for GA) and that `redhat-operators` is available. For disconnected installs, mirror the operator and its dependencies.
- **SpireServer not starting:** Check PVC capacity (min 1Gi) and that `jwtIssuer` is a valid URL. Inspect `oc describe spireserver cluster -n workload-identity-manager` and operator logs.
- **SpireAgent not connecting:** Verify `spireServerAddress` and `spireServerPort` reachable from nodes; check network policies and firewall.
- **CSI volume mount fails:** Ensure `SpiffeCSIDriver` is installed and `agentSocketPath` matches the agent socket path. Confirm the trust domain and cluster name match across CRs.
- **Immutable fields:** In GA, fields such as `trustDomain`, `clusterName`, and persistence settings are immutable after creation. Plan values before first apply.

## Next Steps

- Register workloads with SPIRE and integrate applications with the Workload API.
- Configure [confidential containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/1.11/html-single/deploying_confidential_containers/index) for data-in-use protection.
- Deploy [Red Hat Trusted Software Supply Chain](https://www.redhat.com/en/resources/trusted-software-supply-chain-datasheet) for build-time assurance.
