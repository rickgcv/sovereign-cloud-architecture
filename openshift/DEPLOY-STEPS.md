# Fix ImagePullBackOff — deploy in this order

ImagePullBackOff usually means the image **does not exist yet** in the cluster (build not run or failed). Do the steps below in order.

## 1. Log in and use your project

```bash
oc login --token=YOUR_TOKEN --server=YOUR_SERVER
oc project sovereign-cloud-docs
```

(Replace with your project name if different.)

## 2. Create ImageStream and BuildConfig (no Deployment yet)

```bash
oc apply -f openshift/is.yaml
oc apply -f openshift/buildconfig.yaml
```

## 3. Run the build and wait until it finishes

```bash
oc start-build sovereign-cloud-website --follow
```

Wait until you see something like: `Successfully built and pushed ... Push successful`.  
If the build fails, fix the build (e.g. Git access, Dockerfile) before continuing.

## 4. Confirm the image exists in the internal registry

```bash
oc get is sovereign-cloud-website
oc get istag sovereign-cloud-website:latest
```

You should see the `latest` tag and a digest.

## 5. Get the exact image pull spec (optional)

```bash
oc get istag sovereign-cloud-website:latest -o jsonpath='{.image.dockerImageReference}'
```

Copy that value; you can use it in step 6 if the Deployment still can’t pull.

## 6. Create Deployment, Service, and Route

```bash
oc apply -f openshift/deployment.yaml
oc apply -f openshift/service.yaml
oc apply -f openshift/route.yaml
```

The Deployment has an **image stream trigger**: when `sovereign-cloud-website:latest` exists, OpenShift will set the container image from the ImageStream. If the build already completed in step 3, the trigger should set the image and the pod should start.

## 7. If the pod is still ImagePullBackOff (pod shows short name `sovereign-cloud-website:latest`)

The ReplicaSet may still have the old image. **Force the Deployment to use the image from the internal registry:**

```bash
oc set image deployment/sovereign-cloud-website \
  sovereign-cloud-website=$(oc get istag sovereign-cloud-website:latest -o jsonpath='{.image.dockerImageReference}')
```

This updates the pod template with the full pull spec (including digest) and triggers a new rollout. Then:

```bash
oc rollout status deployment/sovereign-cloud-website
oc get pods -l app=sovereign-cloud-website
```

Or, if your **project name is not** `sovereign-cloud-docs`, use:

```bash
oc set image deployment/sovereign-cloud-website \
  sovereign-cloud-website=image-registry.openshift-image-registry.svc:5000/YOUR_PROJECT/sovereign-cloud-website:latest
```

## 8. Check the pod and route

```bash
oc get pods -l app=sovereign-cloud-website
oc get route sovereign-cloud-website
```

Open the route URL in your browser.

---

**Summary:** Build first so the image exists in the internal registry, then create (or update) the Deployment. The image must be in the same project’s ImageStream for the trigger or the manual `oc set image` to work.
