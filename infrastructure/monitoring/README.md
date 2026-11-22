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

- Prometheus: 50Gi for metrics data (60 days / 30GB retention, not backed up)
- Grafana: 2Gi for dashboards and configuration (backed up)
- AlertManager: 2Gi for silences / notification state (not backed up)

## Resource Configuration

This is configured as a **lightweight** monitoring solution with minimal resource requirements:

- Prometheus: 100m CPU / 712Mi RAM (requests)
- Grafana: 250m CPU / 428Mi RAM (requests)
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

### Credentials

Grafana's admin login comes from Vaultwarden (item `monitoring/monitoring-grafana-admin`) via ESO, see `manifests/grafana-admin.externalsecret.yaml`.

## Alerting

Alerts go to the homelab Discord channel, and only for things that need action. Each rule's `description` says what to do.

| Piece | Where |
|---|---|
| Homelab rules (disks, Longhorn, backups, OOM, nodes, certs) | `manifests/prometheusrule-homelab.yaml` |
| Default-rule tuning (disabled rules, `TargetDown` 30m) | `values.yaml` → `defaultRules.disabled`, `customRules` |
| Routing, receivers, inhibit rules | `manifests/alertmanager-config.yaml` (global `AlertmanagerConfig`) |
| Discord message template | ConfigMap `alertmanager-templates` (same file) |
| Webhook URLs | Vaultwarden `monitoring/alertmanager-notifications` → ESO → Secret `alertmanager-notifications` |

Routing:
- `critical`: Discord with a 🔴 title, reminder every 6h while firing.
- `warning`: Discord with a 🟠 title, reminder every 24h.
- `info`/`none`: dropped.
- `Watchdog`: pings healthchecks.io every 5 min (dead-man's switch). healthchecks.io notifies by email and Discord when the pings stop, which means the cluster, Alertmanager or the internet is down.
- While `HomelabNodeDown` fires, its follow-up symptoms (TargetDown, degraded volumes, replica mismatches, ...) are muted.

Why it is built this way:
- **AlertmanagerConfig instead of `alertmanager.config`.** Alertmanager 0.27 (chart 67.11) rejects Discord `webhook_url_file`, and the webhook URL must not be in git. The operator inlines it from the Secret instead.
- **No `@here`.** Discord's `content` field needs Alertmanager ≥ 0.28 and a newer operator. Revisit on the next kube-prometheus-stack upgrade. Until then, set the channel's notification setting to "All Messages" on your phone; alerts are rare enough for that.
- **Volume fullness uses `kubelet_volume_stats_*`, not `longhorn_volume_actual_size_bytes`.** The latter counts snapshot data and is often over 100 %.
- **The halo-8 HDD only reports SMART data around backups** (see `smartctl-exporter.yaml`), so its rules look back up to 8 days.
- **halo-0 idles around 84 °C,** so `NodeTemperatureHigh` fires only above 85 °C (the Pi 5 hard-throttle point) for 30 min.

Silence or inspect alerts:

```bash
kubectl -n monitoring port-forward svc/monitoring-helm-kube-prome-alertmanager 9093
# http://localhost:9093 -> New Silence
```

Send a test alert (resolves after 5 min):

```bash
kubectl -n monitoring port-forward svc/monitoring-helm-kube-prome-alertmanager 9093 &
curl -s -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname": "TestAlert", "severity": "warning", "namespace": "monitoring"},
  "annotations": {"summary": "Test alert", "description": "Ignore me."},
  "endsAt": "'"$(date -u -d '+5 min' +%Y-%m-%dT%H:%M:%SZ)"'"}]'
```

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
  - `prometheusrule-homelab.yaml`, `alertmanager-config.yaml`, `alertmanager-notifications.externalsecret.yaml`: alerting (see above)
  - `smartctl-exporter.yaml`, `grafana-dashboard-*.yaml`: SMART exporter and dashboards

To modify the configuration, edit the relevant files and commit the changes. ArgoCD will automatically sync the updates.
