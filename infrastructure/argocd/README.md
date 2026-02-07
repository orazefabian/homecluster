# ArgoCD Configuration

This directory contains the ArgoCD ApplicationSets and Applications that manage the entire homecluster deployment.

## Structure

The configuration is now split into multiple files for better organization and proper Helm chart support:

### ApplicationSets

1. **argocd-manifests-applicationset.yaml**
   - Manages all manifest-based applications and infrastructure components
   - Uses ArgoCD's `directory` source type with `recurse: true`
   - Includes:
     - All apps in the `apps/` directory
     - Manifest-only infrastructure: metallb, secrets-backup, reloader, kite

2. **argocd-helm-applicationset.yaml**
   - Manages Helm chart-based infrastructure components
   - Uses ArgoCD's `helm` source type for proper Helm integration
   - Includes:
     - cert-manager (Helm chart)
     - ingress-nginx (Helm chart)
     - longhorn (Helm chart)

### Individual Applications

3. **argocd-cert-manager-manifests.yaml**
   - Manages additional cert-manager manifests (ClusterIssuers, Certificates)
   - Located in `infrastructure/cert-manager/manifests/`
   - Applied separately to avoid conflicts with the Helm chart
   - Note: CRDs are now managed by the Helm chart via `installCRDs: true`

4. **argocd-longhorn-manifests.yaml**
   - Manages additional longhorn manifests (Ingress, Certificates)
   - Located in `infrastructure/longhorn/manifests/`
   - Applied separately to avoid conflicts with the Helm chart

5. **argocd-ingress.yaml**
   - Manages the ArgoCD ingress configuration

## Why This Structure?

The previous single ApplicationSet used `directory.recurse: true` for all deployments, which caused issues with Helm charts:

- **Problem**: Helm charts were being processed as plain YAML manifests, causing resources to appear out of sync in ArgoCD
- **Solution**: Split into separate ApplicationSets based on deployment method (manifests vs. Helm)

### Benefits

1. **Proper Helm Integration**: Helm charts are now deployed using ArgoCD's Helm source type, ensuring all chart resources are tracked correctly
2. **Better Sync Status**: All resources from Helm charts are now visible and properly synced in ArgoCD
3. **Clear Separation**: Easy to understand which components use Helm and which use plain manifests
4. **Flexibility**: Easy to add new Helm charts or manifest-based deployments without confusion

## Adding New Applications

### For Manifest-Based Deployments

Add a new element to the `argocd-manifests-applicationset.yaml` generators list:

```yaml
- name: my-new-app
  path: ./apps/my-new-app/manifests
  namespace: my-namespace
```

### For Helm Chart Deployments

Add a new element to the `argocd-helm-applicationset.yaml` generators list:

```yaml
- name: my-helm-app
  chartPath: ./infrastructure/my-helm-app
  namespace: my-namespace
  valuesFile: values.yaml
```

## Sync Policy

All applications use the following sync policy:
- **Automated Sync**: Resources are automatically applied to the cluster
- **Self-Healing**: Any drift from the desired state is corrected
- **CreateNamespace**: Namespaces are created automatically if they don't exist
- **Prune**: Disabled (set to `false`) to prevent accidental deletions
- **ServerSideApply**: Enabled to handle large CRDs (fixes annotation size limit errors for kube-prometheus-stack)

### Why ServerSideApply?

The `ServerSideApply=true` sync option is crucial for Helm charts that include large Custom Resource Definitions (CRDs), such as the kube-prometheus-stack used in the monitoring stack. Without this option, Helm stores the entire manifest in Kubernetes annotations, which have a 262144 byte limit. Large CRDs exceed this limit, causing sync failures with errors like:

```
CustomResourceDefinition.apiextensions.k8s.io "prometheuses.monitoring.coreos.com" is invalid: 
metadata.annotations: Too long: must have at most 262144 bytes
```

Server-Side Apply uses a different mechanism that doesn't rely on annotations for storing manifests, allowing ArgoCD to successfully sync applications with large CRDs.
