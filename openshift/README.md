# Deploy the Sovereign Cloud Architecture website on OpenShift

This directory contains everything needed to run the solution website (AWS-style landing page and deployment guide) on an OpenShift cluster.

## What gets deployed

- **Static website** (HTML, CSS, architecture image) served by **nginx** on port **8080**.
- **BuildConfig** builds the container image from this repository (Dockerfile at repo root).
- **Deployment**, **Service**, and **Route** expose the site inside the cluster and via HTTPS.

## Prerequisites

- OpenShift cluster (4.x) and `oc` logged in with permission to create resources in a project.
- Cluster can pull from GitHub (or you use a private repo and configure build secrets).

## Option 1: Deploy with the template (recommended)

From the repository root (or from this directory, adjust the path to the template):

```bash
# Create a project for the website
oc new-project sovereign-cloud-docs

# Process and apply the template (uses default Git URI and ref)
oc process -f openshift/template.yaml | oc apply -f -

# Important: run the build first so the image exists (avoids ImagePullBackOff)
oc start-build sovereign-cloud-website --follow
```

When the build completes, the Deployment’s image stream trigger will set the image and the pod should start. Get the public URL:

```bash
oc get route sovereign-cloud-website -o jsonpath='https://{.spec.host}'
```

Open that URL in a browser to view the site.

## Option 2: Deploy from local manifests

If you prefer to apply individual files or use a different Git URI/ref:

1. **Create project and ImageStream**

   ```bash
   oc new-project sovereign-cloud-docs
   oc apply -f openshift/is.yaml
   ```

2. **Create BuildConfig** (edit `openshift/buildconfig.yaml` if your repo/ref differ)

   ```bash
   oc apply -f openshift/buildconfig.yaml
   oc start-build sovereign-cloud-website --follow
   ```

3. **Create Deployment, Service, and Route** (after the image is available)

   ```bash
   oc apply -f openshift/deployment.yaml
   oc apply -f openshift/service.yaml
   oc apply -f openshift/route.yaml
   ```

4. **Get the route**

   ```bash
   oc get route sovereign-cloud-website
   ```

## Option 3: Build image elsewhere and deploy

If you build the image outside OpenShift (e.g. CI/CD or local Docker):

1. Build the image (from repo root):

   ```bash
   docker build -t sovereign-cloud-website:latest .
   ```

2. Push to your OpenShift internal registry or another registry OpenShift can pull from.

3. Create only the Deployment, Service, and Route (no BuildConfig). In `deployment.yaml`, set `image` to the full image pull spec (e.g. `image-registry.openshift-image-registry.svc:5000/sovereign-cloud-docs/sovereign-cloud-website:latest` or your external registry URL).

4. Apply:

   ```bash
   oc apply -f openshift/deployment.yaml -f openshift/service.yaml -f openshift/route.yaml
   ```

## Template parameters

When using `template.yaml`, you can override:

| Parameter           | Default                                                  | Description                    |
|--------------------|----------------------------------------------------------|--------------------------------|
| `GIT_URI`          | `https://github.com/rickgcv/sovereign-cloud-architecture.git` | Git repository URL for the build. |
| `GIT_REF`          | `main`                                                  | Branch or tag to build.        |
| `APPLICATION_NAME` | `sovereign-cloud-website`                                | Name used for resources.       |

Example with a fork and branch:

```bash
oc process -f openshift/template.yaml \
  -p GIT_URI=https://github.com/YOUR_ORG/sovereign-cloud-architecture.git \
  -p GIT_REF=my-branch \
  | oc apply -f -
```

## Troubleshooting

- **Pod crashing / CrashLoopBackOff** — Check the pod logs and events:
  ```bash
  oc logs deployment/sovereign-cloud-website --previous
  oc describe pod -l app=sovereign-cloud-website
  ```
  Common causes: (1) Permission denied — the image is built with world-readable files and the deployment runs as UID 101; if your SCC rejects `runAsUser: 101`, remove the `securityContext.runAsUser` from the Deployment and rely on the image’s default user. (2) Wrong port — ensure the container listens on 8080 and the Service/Route target that port. (3) Probes too aggressive — the manifests use higher `initialDelaySeconds`; if the pod still fails, increase them further or temporarily remove the probes to confirm nginx starts.

- **Build fails** — Ensure the cluster can reach the Git URI. For private repos, add a build secret and reference it in the BuildConfig. If the base image `nginxinc/nginx-unprivileged:1.25-alpine` cannot be pulled, use the alternative Dockerfile: in BuildConfig set `dockerStrategy.dockerfilePath` to `Dockerfile.nginx-alpine` and ensure the repo has that file (and update the nginx config for port 8080 if needed).

- **ImagePullBackOff** — The image does not exist in the cluster yet. **Run the build first**, then create or update the Deployment. See **[DEPLOY-STEPS.md](DEPLOY-STEPS.md)** for the exact order (create BuildConfig → run build → then Deployment). The Deployment has an image stream trigger so it picks up the image from the ImageStream after the build. If the pod still can’t pull, set the image manually: `oc set image deployment/sovereign-cloud-website sovereign-cloud-website=$(oc get istag sovereign-cloud-website:latest -o jsonpath='{.image.dockerImageReference}')`.

- **404 on refresh** — The site is static; nginx is configured so `/` serves `index.html`. Subpaths like `/deployment.html` work. If you use a different base path, adjust nginx config and rebuild.

- **Route not showing** — Confirm the Route is created: `oc get route`. If TLS is required by your cluster, the provided Route uses edge termination.

## Files in this directory

| File               | Purpose                                                                 |
|--------------------|-------------------------------------------------------------------------|
| `template.yaml`    | Single template with ImageStream, BuildConfig, Deployment, Service, Route. |
| `buildconfig.yaml`| BuildConfig (Docker build from Git).                                   |
| `is.yaml`         | ImageStream for the built image.                                       |
| `deployment.yaml` | Deployment (one replica, port 8080, probes).                           |
| `service.yaml`    | Service (ClusterIP, port 8080).                                         |
| `route.yaml`      | Route (edge TLS, exposes the service).                                  |

The Dockerfile and website assets live at the repository root and in `website/`, as used by the BuildConfig.
