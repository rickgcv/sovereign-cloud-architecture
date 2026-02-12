# Implement Virtual Control Planes for Managed Clusters

This guide explains how to implement virtual control planes on the management cluster using Red Hat OpenShift Virtualization. Each managed cluster’s control plane runs in its own dedicated virtual machine(s) on the management cluster, isolating it from the data plane (worker nodes) and from other managed clusters.

## Overview

- **Management cluster (hub)** runs RHACM and OpenShift Virtualization.
- **Per managed cluster:** one or more VMs on the hub host that cluster’s control plane (API server, etcd, controller manager, scheduler).
- **Data plane** remains on bare metal worker nodes in the managed cluster (see [Deploy worker nodes on bare metal](deploy-bare-metal-workers-rhacm.md)).

This separation gives operational sovereignty: control plane and data plane are isolated, and each tenant’s control plane runs in dedicated VMs.

## Prerequisites

- **Management cluster** with cluster-admin access.
- **RHACM** installed on the management cluster ([deploy RHACM](deploy-rhacm.md)).
- **OpenShift Platform Plus** (or equivalent) so you can install OpenShift Virtualization.
- **Managed clusters** either existing or to be created; this guide focuses on running their control planes as VMs on the hub.
- **Storage:** a default `StorageClass` for VM disks (e.g. `ocs-storagecluster-ceph-rbd` or another provisioner).
- **Network:** connectivity from control plane VMs to the rest of the hub and to managed-cluster data planes (worker networks).

---

## Step 1: Install OpenShift Virtualization on the Management Cluster

### 1.1 Create namespace and OperatorGroup

Run on the **management cluster**:

```bash
oc create namespace openshift-cnv

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
  - openshift-cnv
EOF
```

### 1.2 Subscribe to the OpenShift Virtualization operator

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kubevirt-hyperconverged
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 1.3 Wait for the operator to be ready

```bash
oc get csv -n openshift-cnv
# Wait until PHASE is Succeeded for the kubevirt-hyperconverged operator
oc wait --for=condition=Available deployment/openshift-cnv-cluster-network-addons-operator -n openshift-cnv --timeout=300s
oc wait --for=condition=Available deployment/openshift-cnv-hco-operator -n openshift-cnv --timeout=300s
```

### 1.4 Create the HyperConverged custom resource

This installs KubeVirt, CDI, and related components:

```bash
cat <<EOF | oc apply -f -
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  featureGates:
    withHostPassthroughCPU: false
  logVerbosityConfig:
    kubevirt:
      virtLauncher: 2
      virtController: 2
      virtHandler: 2
  storageClass: ""   # leave empty to use cluster default StorageClass
EOF
```

### 1.5 Verify OpenShift Virtualization

```bash
oc get pods -n openshift-cnv
oc get hco kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
# Should report True when ready
```

---

## Step 2: Prepare a Dedicated Namespace per Managed Cluster

Use a dedicated namespace for each managed cluster’s control plane VMs so resources and policies are isolated.

On the **management cluster**:

```bash
export MANAGED_CLUSTER_NAME=my-managed-cluster
oc create namespace vcp-${MANAGED_CLUSTER_NAME}
```

Example for multiple clusters:

```bash
for c in cluster-east cluster-west; do oc create namespace vcp-${c}; done
```

---

## Step 3: Create a VM Template for Control Plane Nodes (RHCOS-based)

Each control plane VM typically runs a minimal OS (e.g. RHCOS) with the OpenShift control plane components. Use a DataVolume or PVC backed by a RHCOS image.

### 3.1 Create a DataVolume template from RHCOS image

Replace the RHCOS image URL with one for your OpenShift version (see [OpenShift RHCOS image URLs](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/)).

On the **management cluster**:

```bash
export RHCOS_IMAGE_URL=https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.15/4.15.0/rhcos-4.15.0-x86_64-openstack.qcow2.gz
export VCP_NAMESPACE=vcp-my-managed-cluster

cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: rhcos-control-plane-base
  namespace: ${VCP_NAMESPACE}
spec:
  source:
    http:
      url: ${RHCOS_IMAGE_URL}
  pvc:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
    storageClassName: ""   # use default or e.g. ocs-storagecluster-ceph-rbd
EOF
```

Wait for the DataVolume to be ready (this can take several minutes):

```bash
oc get dv -n ${VCP_NAMESPACE}
oc wait --for=condition=Ready dv/rhcos-control-plane-base -n ${VCP_NAMESPACE} --timeout=600s
```

### 3.2 Create a VirtualMachine for one control plane node

For a single control plane VM per managed cluster (e.g. dev/test), use the base PVC:

```bash
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: control-plane-${MANAGED_CLUSTER_NAME}-0
  namespace: ${VCP_NAMESPACE}
  labels:
    managed-cluster: ${MANAGED_CLUSTER_NAME}
    role: control-plane
spec:
  running: true
  template:
    metadata:
      labels:
        managed-cluster: ${MANAGED_CLUSTER_NAME}
        role: control-plane
    spec:
      domain:
        cpu:
          cores: 4
          sockets: 1
          threads: 1
        memory:
          guest: 8Gi
        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
          rng: {}
        resources:
          requests:
            memory: 8Gi
      volumes:
      - name: rootdisk
        persistentVolumeClaim:
          claimName: rhcos-control-plane-base
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            hostname: control-plane-${MANAGED_CLUSTER_NAME}-0
            runcmd:
            - systemctl restart nm-cloud-setup
      networks:
      - name: default
        pod: {}
  dataVolumeTemplates: []
EOF
```

For **high availability**, create multiple VMs (e.g. `control-plane-${MANAGED_CLUSTER_NAME}-0`, `-1`, `-2`) and ensure they use distinct PVCs (clone from the base DataVolume per VM).

---

## Step 4: Use a Dedicated Network for Control Plane VMs (Optional)

To isolate control plane VM traffic, create a NetworkAttachmentDefinition (NAD) and attach it to the VM.

### 4.1 Create a bridge or overlay network

Example: bridge network for the management cluster nodes:

```bash
cat <<EOF | oc apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: bridge-network
  namespace: ${VCP_NAMESPACE}
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "name": "bridge-network",
      "type": "bridge",
      "bridge": "br0",
      "ipam": {
        "type": "host-local",
        "subnet": "10.100.0.0/24"
      }
    }
EOF
```

Then add this network to the VM `template.spec` (in `spec.template.spec.networks` and `spec.template.spec.domain.devices.interfaces`). Adjust subnet and bridge to match your management cluster network design.

---

## Step 5: Scale to Multiple Control Plane VMs per Cluster (HA)

For three control plane nodes per managed cluster, create three DataVolumes (clones from the base) and three VMs:

```bash
for i in 0 1 2; do
  cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: rhcos-cp-${MANAGED_CLUSTER_NAME}-${i}
  namespace: ${VCP_NAMESPACE}
spec:
  source:
    pvc:
      name: rhcos-control-plane-base
      namespace: ${VCP_NAMESPACE}
  pvc:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 50Gi
EOF
done

oc wait --for=condition=Ready dv/rhcos-cp-${MANAGED_CLUSTER_NAME}-0 dv/rhcos-cp-${MANAGED_CLUSTER_NAME}-1 dv/rhcos-cp-${MANAGED_CLUSTER_NAME}-2 -n ${VCP_NAMESPACE} --timeout=600s
```

Then create three `VirtualMachine` manifests, each with `claimName: rhcos-cp-${MANAGED_CLUSTER_NAME}-0`, `-1`, `-2`, and unique `name`/`hostname`.

---

## Step 6: Integrate with RHACM (View and Manage VMs from the Hub)

RHACM can list and manage VMs across managed clusters. For VMs that run **on the hub** (your control plane VMs), they appear in the hub’s OpenShift Virtualization namespaces.

### 6.1 Enable VM actions in RHACM (optional)

To manage VMs from the RHACM console:

```bash
oc annotate search search-v2-operator -n open-cluster-management virtual-machine-preview='true'
```

### 6.2 Label control plane VMs for backup (optional)

If you use RHACM backup/restore for virtualization, add the label:

```bash
oc label vm control-plane-${MANAGED_CLUSTER_NAME}-0 -n ${VCP_NAMESPACE} cluster.open-cluster-management.io/backup-vm=daily_8am
```

---

## Step 7: Connect Control Plane VMs to the Data Plane

The control plane VMs on the management cluster must reach the worker nodes (data plane) of the managed cluster. Common approaches:

- **Same L2/L3 network:** Use a NAD (e.g. bridge) so control plane VMs get IPs on the same VLAN/subnet as the managed cluster’s control plane network, and ensure routing so workers can reach the API server.
- **VPN or overlay:** Run a small tunnel or overlay (e.g. WireGuard, VXLAN) between the control plane VMs and the managed cluster network.
- **Hosted control planes (Hypershift):** Use [OpenShift Hosted Control Planes](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/hosted_control_planes/) so the control plane runs as pods on the hub; you can schedule those pods on nodes that are themselves VMs (created with OpenShift Virtualization) for isolation.

Document your chosen network design and apply it consistently per managed cluster.

---

## Verification Checklist

- [ ] OpenShift Virtualization is installed and `HyperConverged` is Available on the management cluster.
- [ ] Dedicated namespace exists per managed cluster (e.g. `vcp-<cluster-name>`).
- [ ] At least one control plane VM per managed cluster is `Running` in that namespace.
- [ ] VMs have sufficient CPU/memory (e.g. 4 vCPU, 8 Gi per control plane node).
- [ ] Storage for VM disks is provisioned (DataVolumes/PVCs bound).
- [ ] From RHACM console (optional), VMs are visible and manageable.
- [ ] Network path from control plane VMs to the managed cluster’s data plane is defined and tested.

---

## Troubleshooting

- **VMs not starting:** Check `oc get vmi -n <vcp-namespace>` and `oc describe vmi <name> -n <vcp-namespace>`. Ensure PVCs are bound and storage is available.
- **No default StorageClass:** Set a default or specify `storageClassName` in DataVolume/PVC.
- **Network isolation:** Verify NAD and VM interface configuration; ensure `masquerade` or bridge matches your network design.
- **RHACM not showing VMs:** Confirm the `virtual-machine-preview` annotation and that the Search operator is running.

---

## Next Steps

- [Deploy worker nodes on bare metal](deploy-bare-metal-workers-rhacm.md) in the managed clusters for the data plane.
- [Create a User Defined Network (UDN)](create-udn.md) per managed cluster for network separation.
- Consider [Hosted Control Planes](https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/hosted_control_planes/) for a pod-based control plane on the hub with optional VM-backed nodes for isolation.
