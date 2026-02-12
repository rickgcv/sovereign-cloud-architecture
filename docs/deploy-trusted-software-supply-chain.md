# Deploy Red Hat Trusted Software Supply Chain

This guide explains how to deploy **Red Hat Trusted Software Supply Chain** on OpenShift using **Red Hat Trusted Artifact Signer (RHTAS)**. RHTAS provides a signing and verification framework (Fulcio, Rekor, Trillian, TUF, CTlog) so you can sign and verify container images and Git commits, supporting assurance sovereignty in the sovereign cloud architecture.

## Overview

Red Hat Trusted Software Supply Chain on OpenShift is implemented primarily through **Red Hat Trusted Artifact Signer**, which deploys:

- **Fulcio** – Certificate authority that binds signing identity to OIDC (keyless signing)
- **Rekor** – Transparency log for signature metadata
- **Trillian** – Database backend for Rekor (default or external)
- **TUF (The Update Framework)** – Secure distribution of signing root of trust
- **CTlog** – Certificate transparency log

You must configure at least one **OIDC provider** (e.g. Red Hat build of Keycloak, Google, GitHub, Amazon STS, Microsoft Entra ID) for artifact signing.

## Prerequisites

- **OpenShift Container Platform 4.16 or later**
- **cluster-admin** access
- **OIDC provider** configured (Keycloak, Google, GitHub, etc.) for signing
- Workstation with `oc` installed; for signing/verifying you will need **cosign** 2.2+ and optionally **podman**, **gitsign**, **rekor-cli** (downloadable from the OpenShift web console)

## Resource recommendations

- **Trillian (default / dedicated):** 2 CPU cores, 1 GB RAM, 5 GB storage (production)
- **Trillian (managed / non-production):** 4 CPU cores, 2 GB RAM, 10 GB storage

## Step 1: Install the Red Hat Trusted Artifact Signer operator

The operator installs into the `openshift-operators` namespace by default. You can install via the web console (OperatorHub → search "trusted" → Red Hat Trusted Artifact Signer → Install) or via CLI.

### Option A: Install from OperatorHub (CLI)

Create a Subscription so OLM installs the operator:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: trusted-artifact-signer-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: trusted-artifact-signer-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

**Note:** If the package name differs in your catalog, run `oc get packagemanifests -n openshift-marketplace | grep -i trusted` and use the correct operator name in the Subscription.

### Wait for the operator to be ready

```bash
oc get csv -n openshift-operators | grep -i trusted
```

Wait until the Trusted Artifact Signer CSV shows `PHASE: Succeeded`. After installation, the operator automatically creates the project **trusted-artifact-signer** (if not already present).

```bash
oc get project trusted-artifact-signer
```

## Step 2: Deploy the Trusted Artifact Signer service (Securesign)

Create a **Securesign** custom resource in the `trusted-artifact-signer` namespace. You must configure at least one OIDC issuer under `spec.fulcio.config.OIDCIssuers`.

First, set variables for your OIDC provider (example: Keycloak realm):

```bash
export OIDC_ISSUER_URL="https://keycloak-keycloak-system.apps.<your-cluster-domain>/auth/realms/trusted-artifact-signer"
export OIDC_CLIENT_ID="trusted-artifact-signer"
```

Create the Securesign instance. The exact `apiVersion` and `kind` may vary; run `oc get crd | grep -i securesign` to confirm:

```bash
cat <<EOF | oc apply -f -
apiVersion: securesign.securesign.dev/v1alpha1
kind: Securesign
metadata:
  name: securesign
  namespace: trusted-artifact-signer
spec:
  fulcio:
    config:
      OIDCIssuers:
        - Issuer: "${OIDC_ISSUER_URL}"
          ClientID: "${OIDC_CLIENT_ID}"
          IssuerURL: "${OIDC_ISSUER_URL}"
          Type: email
  # Optional: use external database for Trillian (set create: false and databaseSecretRef)
  trillian:
    database:
      create: true
EOF
```

**If the CRD uses a different structure** (e.g. `spec.fulcio.config.oidcIssuers` in camelCase), adjust the YAML accordingly. You can also create the Securesign from the OpenShift console: **Operators → Installed Operators → Red Hat Trusted Artifact Signer → Securesign tab → Create Securesign**, then switch to YAML view and paste or edit the spec.

**Optional – external database for Trillian:** To use an existing database instead of the operator-created one, set `spec.trillian.database.create: false` and provide `spec.trillian.database.databaseSecretRef.name` pointing to a Secret that contains the database connection details. See [Red Hat documentation](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/1/html/deployment_guide/rhtas-ocp-deploy) for RDS or in-cluster database configuration.

## Step 3: Wait for components to be ready

Watch the RHTAS components until CTlog, Fulcio, Rekor, Trillian, and TUF are ready:

```bash
oc get securesign -n trusted-artifact-signer
oc get fulcio,rekor,trillian,tuf,ctlog -n trusted-artifact-signer
oc get pods -n trusted-artifact-signer
```

In the console: **Operators → Installed Operators → Red Hat Trusted Artifact Signer → Securesign → All instances** and confirm CTlog, Fulcio, Rekor, Trillian, and TUF show as ready.

## Step 4: Configure environment for signing and verification

From a workstation with `oc` and (for signing) **cosign** 2.2+:

```bash
oc project trusted-artifact-signer

# Base hostname of your OpenShift apps domain (e.g. apps.example.com)
export BASE_HOSTNAME=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
export TUF_URL="https://tuf-${BASE_HOSTNAME}"
export COSIGN_FULCIO_URL=$(oc get fulcio -o jsonpath='{.items[0].status.url}' -n trusted-artifact-signer)
export COSIGN_REKOR_URL=$(oc get rekor -o jsonpath='{.items[0].status.url}' -n trusted-artifact-signer)
export COSIGN_MIRROR=$TUF_URL
export COSIGN_ROOT=$TUF_URL/root.json
export COSIGN_OIDC_CLIENT_ID="${OIDC_CLIENT_ID}"
export COSIGN_OIDC_ISSUER="${OIDC_ISSUER_URL}"
export COSIGN_CERTIFICATE_OIDC_ISSUER="${OIDC_ISSUER_URL}"
export COSIGN_YES="true"
export SIGSTORE_FULCIO_URL=$COSIGN_FULCIO_URL
export SIGSTORE_OIDC_ISSUER=$COSIGN_OIDC_ISSUER
export SIGSTORE_REKOR_URL=$COSIGN_REKOR_URL
export REKOR_REKOR_SERVER=$COSIGN_REKOR_URL
```

If using Keycloak in a different namespace, set `OIDC_ISSUER_URL` from your Keycloak route, for example:

```bash
export OIDC_ISSUER_URL=https://$(oc get route keycloak -n keycloak-system -o jsonpath='{.spec.host}')/auth/realms/trusted-artifact-signer
```

Initialize TUF (required before signing):

```bash
cosign initialize
```

## Step 5: Verify deployment by signing and verifying a container image

1. **Sign a test image** (browser may open for OIDC login):

   ```bash
   cosign sign -y <image>:<tag>
   ```

2. **Verify the signature** (replace with the identity used when signing, e.g. email):

   ```bash
   cosign verify --certificate-identity=<signing-email> --certificate-oidc-issuer=$COSIGN_OIDC_ISSUER <image>:<tag>
   ```

You can also use **rekor-cli** (download from OpenShift web console → ? → Command line tools) to query the transparency log, and **gitsign** to sign and verify Git commits. See [Red Hat Trusted Artifact Signer deployment guide](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/1/html/deployment_guide/rhtas-ocp-deploy) for detailed steps.

## Step 6: (Optional) Integrate with pipelines and policy

- **Tekton Chains** – Configure Chains to sign task run outputs and store attestations using RHTAS (Fulcio/Rekor). Point Chains at your Fulcio and Rekor URLs.
- **Enterprise Contract (Conforma)** – Use the `ec` binary (downloadable from the console) to verify image signatures and attestations against policies.
- **ClusterImagePolicy** – Use OpenShift’s sigstore integration to enforce that only signed images are allowed to run; reference your TUF root and OIDC issuer.

## Verification checklist

- [ ] Trusted Artifact Signer operator CSV is `Succeeded` in `openshift-operators`.
- [ ] Project `trusted-artifact-signer` exists and Securesign CR is created.
- [ ] Fulcio, Rekor, Trillian, TUF, and CTlog instances are ready.
- [ ] Pods in `trusted-artifact-signer` are running.
- [ ] `cosign initialize` and `cosign sign` / `cosign verify` work with your OIDC provider.

## Troubleshooting

- **Operator not in catalog:** Ensure OpenShift 4.16+ and that `redhat-operators` is available (or mirror the operator for disconnected installs).
- **Securesign CR not accepted:** Confirm the CRD name and `apiVersion` with `oc get crd | grep -i securesign` and adjust the YAML. Use the console YAML view as reference.
- **Fulcio/Rekor not ready:** Check pod logs and ensure OIDC issuer URL is reachable from the cluster and that the ClientID matches your OIDC client.
- **Cosign sign fails:** Ensure `cosign` is 2.2+, TUF is initialized (`cosign initialize`), and all COSIGN_* / SIGSTORE_* env vars are set correctly.

## Next steps

- [Install and configure Workload Identity Manager](deploy-workload-identity-manager.md) for workload identity.
- Set up [confidential containers](https://interact.redhat.com/share/wjZnZb2avHnp8k0hwjFe) for data-in-use protection.
- Configure Tekton Pipelines and Tekton Chains to sign build outputs with RHTAS.
- See [Red Hat Trusted Software Supply Chain](https://developers.redhat.com/products/trusted-software-supply-chain/getting-started) and [Red Hat Trusted Artifact Signer](https://docs.redhat.com/en/documentation/red_hat_trusted_artifact_signer/1/html-single/deployment_guide/index) for full documentation.
