# Deploy the sovereign cloud solution

This page contains the full deployment guide for the sovereign cloud architecture. Follow the steps below in order for a standard implementation.

---

## Cluster deployment strategy

For a standard implementation, deploy a management cluster to act as the central hub:

1. [Deploy Red Hat Advanced Cluster Management](deploy-rhacm.md) on the management cluster to govern managed clusters.

2. [Implement Virtual Control Planes](deploy-virtual-control-planes.md) on the management cluster using Red Hat OpenShift Virtualization. Each managed cluster's control plane runs on its own dedicated virtual machine to isolate it from the data plane.

3. [Deploy worker nodes on bare metal in the managed clusters](deploy-bare-metal-workers-rhacm.md) to host the actual application workloads.

4. [Create a User Defined Network (UDN)](create-udn.md) per managed cluster to ensure network separation.

---

## Disconnected environments

In the case of disconnected environments, deploy the management cluster as follows:

1. Establish a landing zone (low trust zone) with a bastion host.

2. Configure the bastion host with Red Hat Enterprise Linux and Ansible Core.

3. Use Ansible playbooks to mirror repositories from Red Hat Quay and bootstrap the management cluster deployment into the high trust zone.

---

## Zero Trust concepts implementation

1. Set up the platform to be able to deploy [confidential containers](https://interact.redhat.com/share/wjZnZb2avHnp8k0hwjFe).
2. [Install and configure Workload Identity Manager](deploy-workload-identity-manager.md).
3. [Deploy Red Hat Trusted Software Supply Chain](deploy-trusted-software-supply-chain.md).
