# Monitoring

This directory contains the configuration for the lightweight Kubernetes monitoring solution based on the kube-prometheus-stack Helm chart.

## Components

The monitoring stack includes:

- **Prometheus**: Collects and stores metrics from the cluster
- **Grafana**: Provides visualization dashboards for metrics
- **AlertManager**: Handles alerts from Prometheus
- **kube-state-metrics**: Generates metrics about Kubernetes object states
- **prometheus-node-exporter**: Collects hardware and OS metrics from cluster nodes

## Storage

All components use **Longhorn PVCs** for persistent storage:

- Prometheus: 10Gi for metrics data (15 days retention)
- Grafana: 2Gi for dashboards and configuration
- AlertManager: 2Gi for alert data

## Resource Configuration

This is configured as a **lightweight** monitoring solution with minimal resource requirements:

- Prometheus: 100m CPU / 512Mi RAM (requests)
- Grafana: 50m CPU / 128Mi RAM (requests)
- AlertManager: 25m CPU / 64Mi RAM (requests)
- kube-state-metrics: 25m CPU / 64Mi RAM (requests)
- node-exporter: 50m CPU / 32Mi RAM (requests)

## Access

### Via Ingress (Recommended)

Grafana is accessible via HTTPS through the configured ingress:

```
https://monitoring.halo.fabseit.net
```

The ingress is configured with:
- TLS certificate issued by cert-manager using Let's Encrypt
- nginx ingress controller

### Via Port-Forward (Alternative)

For local access or troubleshooting, you can use port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-helm-grafana 3000:80
```

Then access Grafana at `http://localhost:3000`

### Default Credentials

- Username: `admin`
- Password: The chart generates a random password on first deployment. Retrieve it with:
  ```bash
  kubectl get secret -n monitoring monitoring-helm-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
  ```

> **Note**: The service and secret names use the ArgoCD Application name prefix (`monitoring-helm`) followed by the Grafana subchart name. If you customize the admin password or use `admin.existingSecret` in `values.yaml`, update the secret name accordingly.

## Metrics Collection

The stack collects metrics with the following intervals:
- Scrape interval: 60s
- Evaluation interval: 60s

This configuration balances monitoring capabilities with resource usage.

## Configuration

The configuration is managed through:
- `Chart.yaml`: Defines the Helm chart dependency
- `values.yaml`: Overrides default values for lightweight operation
- `manifests/`: Contains additional Kubernetes resources:
  - `ingress.yaml`: Ingress configuration for Grafana access
  - `certificate.yaml`: Production TLS certificate for monitoring.halo.fabseit.net
  - `certificate-dev.yaml`: Development/staging TLS certificate

To modify the configuration, edit the relevant files and commit the changes. ArgoCD will automatically sync the updates.
