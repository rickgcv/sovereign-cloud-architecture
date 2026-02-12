# Sovereign Cloud Architecture — Solution website

This folder contains the static website that presents the sovereign cloud solution in an AWS Solutions–style layout (Overview, Benefits, Architecture, About this deployment, Deploy the solution).

## Contents

- **index.html** — Main solution page (overview, benefits, architecture image, requirements, deploy CTA).
- **deployment.html** — Deployment guide page (cluster strategy, disconnected, Zero Trust) with links to the repo docs.
- **css/style.css** — Styles for layout, cards, and responsive behavior.
- **nginx.conf** — Nginx server config (port 8080, static files).

The architecture image is provided at build time from the repository root (`images/sovereign-cloud-overview.png`) and copied into the container.

## Run locally

From the repository root, serve the site with any static server. For example, with Python:

```bash
cd website && python3 -m http.server 8000
```

Then open http://localhost:8000 (the image will be missing unless you copy `../images/sovereign-cloud-overview.png` to `website/images/`).

## Deploy on OpenShift

The image is built from the **repository root** (see root **Dockerfile**). To deploy on OpenShift, use the manifests in **openshift/**:

See **[openshift/README.md](../openshift/README.md)** for full instructions (template, BuildConfig, Deployment, Service, Route).

Quick start:

```bash
oc new-project sovereign-cloud-docs
oc process -f openshift/template.yaml | oc apply -f -
oc start-build sovereign-cloud-website --follow
oc get route sovereign-cloud-website
```
