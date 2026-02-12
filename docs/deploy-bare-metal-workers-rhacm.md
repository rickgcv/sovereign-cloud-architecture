# Deploy Worker Nodes on Bare Metal in Managed Clusters Using RHACM

This guide explains how to deploy worker nodes on bare metal in Red Hat Advanced Cluster Management (RHACM) managed clusters, so application workloads run on physical servers as required by the sovereign cloud architecture.

## Prerequisites

- **RHACM hub** – Red Hat Advanced Cluster Management installed on the management cluster ([deploy RHACM](deploy-rhacm.md)).
- **Managed cluster** – An OpenShift cluster already created and imported into RHACM, or you will create one with bare metal workers (see paths below).
- **Bare metal hosts** – Physical servers that meet [OpenShift bare metal requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/installing_on_bare_metal/preparing-to-install-on-bare-metal):
  - Minimum 8 vCPUs, 32 GB RAM, 120 GB disk per worker
  - BMC (IPMI, Redfish) for out-of-band management
  - PXE boot or virtual media capability
  - Network connectivity to the cluster network and (if used) Assisted Installer
- **Bootstrap/Assisted Installer** (for new clusters) – Optional: on-premise Assisted Installer or connection to Red Hat Hybrid Cloud Console for agent-based installs.

You can either **create a new managed cluster** with bare metal workers from the start, or **add bare metal workers to an existing managed cluster**. Both paths are outlined below.

---

## Path A: Create a New Managed Cluster with Bare Metal Workers (Agent-Based Install)

Use this path when you are provisioning a new OpenShift cluster that will be managed by RHACM and should have only bare metal worker nodes.

### Step 1: Create a namespace for the cluster on the hub

From the RHACM hub (management cluster):

```bash
export CLUSTER_NS=my-managed-cluster   # your managed cluster name
oc create namespace ${CLUSTER_NS}
```

### Step 2: Create an InfraEnv for bare metal agents

An `InfraEnv` defines the image and configuration that bare metal hosts will use to become OpenShift nodes (via the agent-based installer).

```bash
cat <<EOF | oc apply -f -
apiVersion: agent.open-cluster-management.io/v1beta1
kind: InfraEnv
metadata:
  name: ${CLUSTER_NS}
  namespace: ${CLUSTER_NS}
spec:
  clusterRef:
    name: ${CLUSTER_NS}
    namespace: ${CLUSTER_NS}
  pullSecretRef:
    name: pull-secret
  sshAuthorizedKey: "<your-ssh-public-key>"
  agentLabels:
    cluster: ${CLUSTER_NS}
EOF
```

Create the `pull-secret` in `${CLUSTER_NS}` if it does not exist (same pull secret used for OpenShift):

```bash
oc create secret generic pull-secret -n ${CLUSTER_NS} --from-file=.dockerconfigjson=<path-to-pull-secret.json> --type=kubernetes.io/dockerconfigjson
```

### Step 3: Create AgentClusterInstall (ACI)

`AgentClusterInstall` defines the OpenShift version, network, and cluster configuration for the future managed cluster.

```bash
cat <<EOF | oc apply -f -
apiVersion: extensions.hive.openshift.io/v1beta1
kind: AgentClusterInstall
metadata:
  name: ${CLUSTER_NS}
  namespace: ${CLUSTER_NS}
spec:
  clusterDeploymentRef:
    name: ${CLUSTER_NS}
  imageSetRef:
    name: openshift-v4.15.0   # match your desired OpenShift version
  networking:
    clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
    serviceNetwork:
    - 172.30.0.0/16
  provisionRequirements:
    controlPlaneAgents: 3    # 3 control plane nodes
    workerAgents: 3          # 3 bare metal workers
  sshPublicKey: "<your-ssh-public-key>"
EOF
```

Adjust `imageSetRef.name` to an available `ClusterImageSet` on the hub (e.g. `oc get clusterimageset`).

### Step 4: Create ClusterDeployment

The `ClusterDeployment` ties the cluster to RHACM and the Assisted Installer.

```bash
cat <<EOF | oc apply -f -
apiVersion: hive.openshift.io/v1
kind: ClusterDeployment
metadata:
  name: ${CLUSTER_NS}
  namespace: ${CLUSTER_NS}
spec:
  baseDomain: example.com
  clusterName: ${CLUSTER_NS}
  platform:
    agentBareMetal:
      agentSelector:
        matchLabels:
          cluster: ${CLUSTER_NS}
  pullSecretRef:
    name: pull-secret
  clusterMetadata:
    clusterID: ""
    infraID: ""
EOF
```

### Step 5: Boot bare metal hosts and bind them to the cluster

1. Get the ISO or minimal image URL from the `InfraEnv` (or use Discovery image for zero-touch):

   ```bash
   oc get infraenv ${CLUSTER_NS} -n ${CLUSTER_NS} -o jsonpath='{.status.isoDownloadURL}'
   ```

2. Boot each bare metal host from this image (or PXE using the same). Once they register, they appear as `Agent` resources:

   ```bash
   oc get agents -n ${CLUSTER_NS}
   ```

3. Approve and assign agents to control plane or worker role. Agents with the right `cluster` label will be used by the `AgentClusterInstall`. You can set installation disk and role via `Agent` spec or via console.

4. When the required number of `controlPlaneAgents` and `workerAgents` are approved, the installation starts. Monitor:

   ```bash
   oc get agentclusterinstall ${CLUSTER_NS} -n ${CLUSTER_NS}
   oc get clusterdeployment ${CLUSTER_NS} -n ${CLUSTER_NS}
   ```

### Step 6: Import the cluster into RHACM (if not auto-imported)

If the cluster is not automatically imported as a managed cluster, create a `ManagedCluster` and optionally use the import workflow:

```bash
oc get clusterdeployment ${CLUSTER_NS} -n ${CLUSTER_NS} -o jsonpath='{.metadata.labels.hive\.openshift\.io/cluster-type}'
# After install completes, the cluster may auto-import; otherwise use RHACM console "Import cluster" or apply ManagedCluster + KlusterletConfig as per RHACM docs.
```

Verify from the hub:

```bash
oc get managedcluster
```

---

## Path B: Add Bare Metal Worker Nodes to an Existing Managed Cluster

Use this path when you already have a managed OpenShift cluster and want to add more worker nodes on bare metal. This requires the **Metal³ (Bare Metal Operator)** and **Ironic** to be available to that cluster (e.g. cluster was installed with bare metal or you have a provisioning network).

### Step 1: Ensure Metal³ is available on the managed cluster

Switch to the managed cluster (or use `oc --context` / `oc -n <cluster>` with RHACM). Check for Bare Metal Operator and `BareMetalHost`:

```bash
oc get pods -n openshift-machine-api
oc get baremetalhosts -n openshift-machine-api
```

If Metal³ is not installed, you must deploy it and Ironic first (see [OpenShift docs - Installing the Metal³ operator](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/metal3_install)).

### Step 2: Create a secret for the BMC (out-of-band) credentials

On the **managed cluster**:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: worker-bmc-credentials
  namespace: openshift-machine-api
type: Opaque
data:
  username: <base64-encoded-bmc-username>
  password: <base64-encoded-bmc-password>
EOF
```

### Step 3: Add BareMetalHost resources for each new worker

On the **managed cluster**, create one `BareMetalHost` per physical server:

```bash
cat <<EOF | oc apply -f -
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-0
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: <infra-id>   # from cluster
spec:
  online: true
  bootMACAddress: "AA:BB:CC:DD:EE:02"
  bmc:
    address: redfish-virtualmedia://192.168.1.10/redfish/v1/Systems/1
    credentialsName: worker-bmc-credentials
  bootMode: UEFI
  rootDeviceHints:
    deviceName: /dev/sda
EOF
```

Repeat for `worker-1`, `worker-2`, etc., with unique `name`, `bootMACAddress`, and BMC `address`.

### Step 4: Create a MachineSet for bare metal workers

On the **managed cluster**, create a `MachineSet` that uses the `BareMetalHost` provider. You need the correct **infra ID** and **template** from an existing machine (control plane or worker):

```bash
oc get machines -n openshift-machine-api -o wide
oc get machine <existing-worker> -n openshift-machine-api -o yaml
```

Example `MachineSet` (adjust `clusterID`, `infraID`, and provider spec to match your cluster):

```bash
cat <<EOF | oc apply -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  name: worker-baremetal-0
  namespace: openshift-machine-api
spec:
  replicas: 3
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: <infra-id>
      machine.openshift.io/cluster-api-machineset: worker-baremetal-0
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: <infra-id>
        machine.openshift.io/cluster-api-machineset: worker-baremetal-0
    spec:
      providerSpec:
        value:
          apiVersion: baremetal.cluster.k8s.io/v1alpha1
          kind: BareMetalMachineProviderSpec
          image:
            url: ""
            checksum: ""
          userData:
            name: worker-user-data
            namespace: openshift-machine-api
          rootDeviceHints:
            deviceName: /dev/sda
EOF
```

The exact `providerSpec` depends on your OpenShift and Metal³ versions; use `oc get machineset -n openshift-machine-api -o yaml` and clone/adjust from an existing MachineSet.

### Step 5: Verify new workers from the hub (RHACM)

From the **RHACM hub**, confirm the managed cluster shows the new nodes:

```bash
oc get managedcluster <cluster-name> -o wide
```

From the **managed cluster**, confirm machines and nodes:

```bash
oc get machines -n openshift-machine-api
oc get nodes -l node-role.kubernetes.io/worker
```

---

## Managing Bare Metal Workers via RHACM Policies (Optional)

You can use RHACM policies to push configuration to managed clusters (e.g. node labels, taints, or MCP/MachineConfig). Example: apply a **ConfigurationPolicy** that adds a label to worker nodes (run on the **hub**):

```bash
cat <<EOF | oc apply -f -
apiVersion: policy.open-cluster-management.io/v1
kind: ConfigurationPolicy
metadata:
  name: label-bare-metal-workers
  namespace: open-cluster-management
spec:
  remediationAction: enforce
  severity: low
  objectTemplates:
  - complianceType: musthave
    objectDefinition:
      apiVersion: machineconfiguration.openshift.io/v1
      kind: MachineConfig
      metadata:
        name: 99-bare-metal-worker-labels
      spec:
        config:
          ignition:
            version: 3.2.0
        machineConfigPoolSelector:
          matchLabels:
            pools.operator.machineconfiguration.openshift.io: worker
EOF
```

Bind this policy to the right managed cluster using a `PlacementRule` or `Placement` as in [create-udn.md](create-udn.md).

---

## Verification Checklist

- [ ] Managed cluster appears in `oc get managedcluster` on the hub.
- [ ] Worker nodes are bare metal: `oc get nodes -o wide` on the managed cluster shows physical hosts.
- [ ] Workers are schedulable: `oc get nodes` shows `Ready` and no taints (or intended taints).
- [ ] From the hub, RHACM console shows the cluster and node count.

## Troubleshooting

- **Agents not appearing (Path A):** Check `InfraEnv` ISO/URL, network, and that hosts boot from the correct image. Check `oc get agents -n <cluster-ns>`.
- **Installation stuck (Path A):** Inspect `AgentClusterInstall` and cluster deployment conditions: `oc describe agentclusterinstall -n <cluster-ns>`.
- **BareMetalHosts not provisioning (Path B):** Check `oc get baremetalhosts -n openshift-machine-api` and `oc describe baremetalhost <name>`. Ensure BMC credentials and network (PXE/Redfish) are correct.
- **MachineSet not creating machines (Path B):** Ensure `BareMetalHost` objects are `provisioned` and that the MachineSet’s `providerSpec` and `infraID` match the cluster.

## Next Steps

- [Create a User Defined Network (UDN)](create-udn.md) per managed cluster for network separation.
- Configure monitoring and compliance policies in RHACM for the new workers.
