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

After deployment, Grafana can be accessed via port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-grafana 3000:80
```

Default credentials:
- Username: `admin`
- Password: `admin` (should be changed after first login)

## Metrics Collection

The stack collects metrics with the following intervals:
- Scrape interval: 60s
- Evaluation interval: 60s

This configuration balances monitoring capabilities with resource usage.

## Configuration

The configuration is managed through:
- `Chart.yaml`: Defines the Helm chart dependency
- `values.yaml`: Overrides default values for lightweight operation

To modify the configuration, edit `values.yaml` and commit the changes. ArgoCD will automatically sync the updates.
