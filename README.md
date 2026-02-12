# Build a sovereign cloud

Design and deploy a sovereign cloud platform to ensure control over data location, operational independence, and compliance with local regulations.

---

## Overview

This solution enables you to build and operate a **sovereign cloud**—a platform where data location, operational control, and compliance stay in your hands. Digital sovereignty rests on four pillars:

- **Technical sovereignty** — Run workloads without dependence on a provider’s infrastructure or software, and protect them from extra-territorial interference and scrutiny.

- **Operational sovereignty** — Gain visibility and control over provider operations: provisioning, performance, and monitoring of physical and digital access. This architecture uses separation of control planes and data planes, with virtualized control planes per cluster.

- **Assurance sovereignty** — Independently verify and assure the integrity, security, and reliability of systems and processes, including resilience of critical services. The platform is highly available and resilient, supports moving workloads across locations, and builds a trusted software supply chain.

- **Data sovereignty** — Control where data lives and who can access it, and prevent unauthorized cross-border access. The platform applies Zero Trust security and confidential computing to achieve this.

---

## Key features

### Sovereign Cluster as a Service

Let customers deploy their own clusters with a strict operational and physical boundary between the platform provider and tenants. Supports technical and operational sovereignty.

### Sovereign Virtual Machine as a Service

The same sovereign boundaries and isolation at the virtual machine level, for VM-based tenant offerings.

### Observability, auditability, and cost control

Implement and automate auditing, monitoring, and compliance from build-time to runtime, and give customers clear visibility of their spend. Supports operational sovereignty.

### Technology and operational autonomy

Keep the platform operationally autonomous, resilient, and built from trusted, verifiable software components. Supports technical and assurance sovereignty.

### Encrypted data control

Apply cryptographic controls so tenant data remains confidential at-rest, in-use, and in transit. Supports data sovereignty.

---

## Architecture overview

The solution uses a **hub-and-spoke architecture** that integrates the following components:

- **Management platform** — Centralized cluster running automation and GitOps to manage the lifecycle of managed platforms.
- **Managed platform** — Red Hat OpenShift clusters where workloads run, with virtualized worker nodes.
- **Virtual control planes** — Decoupled control planes on dedicated VMs in the management cluster for isolation.
- **Attestation service** — Verifies that workloads run in a Trusted Execution Environment (TEE) so data in use is not visible to platform operators.
- **Identity verification service** — Provides cryptographic identity for workloads and reduces reliance on shared secrets.

![Sovereign cloud architecture](images/sovereign-cloud-overview.png)

---

## Minimum requirements

| | |
|--|--|
| **Version** | 1.0 |
| **Author** | Sovereign Cloud Architecture |
| **Est. deployment time** | Varies by scale (management cluster, number of managed clusters, and automation maturity) |
| **Estimated cost** | Infrastructure-dependent (bare metal, OpenShift subscriptions, and optional managed services) |

### Hardware

- **Bare metal compute nodes** — Required for worker nodes that run both VMs and containers. Major vendors (e.g. Dell, HP, IBM, Lenovo) are certified for these deployments.
- **Trusted hardware** — Processors with support for Trusted Execution Environments (TEE) for confidential computing (e.g. AMD SEV-SNP or Intel SGX/TDX).

### Software

- **Red Hat Enterprise Linux** — Base operating system for the sovereign cloud.
- **Red Hat OpenShift Platform Plus** — Foundation for container and cluster management.
- **Red Hat Advanced Cluster Management** — Lifecycle management of clusters.
- **Red Hat OpenShift Virtualization** — Virtual machines for control planes and legacy workloads.
- **Red Hat Workload Identity Manager**, **Red Hat Build of Trustee**, **OpenShift Sandboxed Containers** — Zero trust and confidential computing.
- **Red Hat OpenShift GitOps** — Automated deployment and configuration management.
- **Ansible Automation Platform** — Orchestration of infrastructure lifecycle automation.

---

## Deploy the solution

Everything you need to deploy this sovereign cloud architecture is in the deployment guide. It covers cluster deployment strategy, disconnected environments, and Zero Trust implementation, with step-by-step links to detailed docs.

**[Open deployment guide →](docs/deployment.md)**
