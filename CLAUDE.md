# homecluster-helm

GitOps repository for a k3s home cluster managed via ArgoCD. All workloads live in the `halo` namespace unless otherwise noted.

## Repository Structure

```
apps/          # Application manifests (Deployments, Services, Ingresses, PVCs)
infrastructure/ # Cluster infrastructure (ArgoCD, MetalLB, Longhorn, cert-manager, ingress-nginx, ...)
helper/        # Utility scripts (e.g. restore-manifests)
```

ArgoCD watches this repo and auto-syncs everything. Two ApplicationSets:
- **manifest-based** (`argocd-manifests-applicationset.yaml`): plain YAML apps and infra
- **Helm-based** (`argocd-helm-applicationset.yaml`): cert-manager, ingress-nginx, longhorn

ServerSideApply is enabled cluster-wide to handle oversized CRD annotations (kube-prometheus-stack hits the 262 KB annotation limit without it). Prune is disabled to prevent accidental deletions.

---

## Network & IP Layout

| IP | Role |
|----|------|
| `192.168.8.1` | FritzBox router / DHCP / DNS relay |
| `192.168.8.30` | ingress-nginx LoadBalancer (all HTTP/HTTPS ingress) |
| `192.168.8.36` | Home Assistant direct LoadBalancer (port 8123) |
| `192.168.8.51` | WireGuard VPN (UDP 51820) |
| `192.168.8.53` | Pi-hole DNS (TCP/UDP 53) |
| `192.168.8.98` | NFS backup server (HDD + SSD targets) |

MetalLB pool: `192.168.8.30–192.168.8.80` (Layer 2 / ARP).

---

## DNS Architecture

`fabseit.net` is a public domain managed on Cloudflare. Internal services resolve to private IPs — this requires the FritzBox DNS rebind protection exception described below.

### Resolution chain (LAN clients)

```
Client → FritzBox (192.168.8.1) → Pi-hole (192.168.8.53) → Cloudflare / upstream
```

- FritzBox DHCP advertises **itself** (`192.168.8.1`) as the DNS server for all clients.
- FritzBox upstream DNS is set to Pi-hole (`192.168.8.53`) with `9.9.9.9` as fallback.
- **DNS rebind protection exception**: `fabseit.net` must be whitelisted in FritzBox (Heimnetz → Netzwerk → DNS-Rebind-Schutz). Without it, FritzBox blocks responses where a public domain resolves to a private IP.

### Headscale (Tailscale-compatible VPN)

Configured at `apps/headscale/server/manifests/configmap.yaml`:
- `override_local_dns: true` — Tailscale takes over DNS on clients (required; with `false` the split DNS rules are silently ignored on many OSes)
- Global fallback: `9.9.9.9`
- Split DNS: `fabseit.net → 192.168.8.53`, `data.home → 192.168.8.53`
- Subnet router pod advertises `192.168.8.0/24` so Tailscale clients can reach `192.168.8.53` remotely

### WireGuard VPN

DNS queries from WireGuard peers are DNAT'd to `192.168.8.53:53` via iptables rules injected by an init container. Peers use `ALLOWEDIPS=0.0.0.0/0` (full tunnel).

---

## TLS / Certificates

cert-manager with two ClusterIssuers (prod + staging), both using Cloudflare DNS-01 challenge.

Wildcard certificates issued per namespace:
- `halo` namespace: `*.halo.fabseit.net` + `*.fabseit.net` → secret `local-fabseit-net-prod-tls`
- `argocd` namespace: `argocd.halo.fabseit.net` → secret `local-fabseit-net-argocd-prod-tls`
- `longhorn-system`: `longhorn.halo.fabseit.net` → its own secret

---

## Storage (Longhorn)

All PVCs use `storageClassName: longhorn` and `accessModes: ReadWriteOnce`.

**Important**: Because PVCs are RWO, all Deployments that have persistent storage use `strategy: Recreate` (not RollingUpdate). A rolling update would try to schedule a new pod before the old one releases the volume.

### Backup schedule

PVCs opt into backup groups via labels:

| Label | Schedule | Retain |
|-------|----------|--------|
| `recurring-job-group.longhorn.io/default` | Every Tuesday 01:00 | 2 |
| `recurring-job-group.longhorn.io/main` | Every Saturday 01:00 | 2 |
| `recurring-job.longhorn.io/s3-monthly-backup` | 1st of month 02:00 | 2 |

Backup targets:
- NFS HDD: `nfs://192.168.8.98:/mnt/backup-data`
- NFS SSD: `nfs://192.168.8.98:/mnt/ssd-data/longhorn-backups`
- S3: Hetzner Object Storage `eu-central` (bucket `backup-halo-store`)

---

## Applications

All in namespace `halo`.

| App | Ingress | Notes |
|-----|---------|-------|
| Home Assistant | `homeassistant.halo.fabseit.net`, `homeassistant.fabseit.net` | Also direct on `192.168.8.36:8123`. Pinned to node with label `homeassistant=true` — needs ConBee II Zigbee stick at `/dev/ttyACM0`. Co-located Postgres 15. |
| Pi-hole | `pihole.halo.fabseit.net` | DNS at `192.168.8.53`. Two PVCs: `pihole-config` (6 Gi) and `pihole-dnsmasq` (1 Gi). |
| Immich | `immich.halo.fabseit.net` | Photo management. Separate Postgres + Redis deployments. |
| Paperless-ngx | `paperless.halo.fabseit.net` | Document management. Separate Postgres + Redis deployments. |
| n8n | `n8n.halo.fabseit.net`, `n8n.fabseit.net` | Workflow automation. Separate Postgres deployment. |
| Bitwarden | `bitwarden.halo.fabseit.net`, `bitwarden.fabseit.net` | Password manager. |
| Heimdall | `dashboard.halo.fabseit.net`, `dashboard.fabseit.net` | App dashboard. |
| Headscale | `vpn.fabseit.net` | Self-hosted Tailscale control plane. TLS handled directly by headscale (Let's Encrypt HTTP-01), not via ingress-nginx. |
| Headplane | `headplane.halo.fabseit.net` | Headscale web UI. |
| WireGuard | `192.168.8.51:51820` (UDP) | VPN. Pinned away from `halo-8` node. Multiple peers configured (see deployment env `PEERS`). |
| Filebrowser | `filebrowser.halo.fabseit.net` | Web file manager. |
| Pingvin Share | `pingvin.halo.fabseit.net` | File sharing. |
| Uptime Kuma | `uptime.halo.fabseit.net` | Uptime monitoring. |
| Speedtest | `speedtest.halo.fabseit.net` | Network speed testing. |
| Monitoring | `monitoring.halo.fabseit.net` | Prometheus + Grafana (kube-prometheus-stack). |
| Samba Share | — | SMB file share, no ingress. |
| DDClient | — | Dynamic DNS updater, no ingress. |

---

## Key Secrets

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `regcred` | `halo` | Image pull secret |
| `local-fabseit-net-prod-tls` | `halo` | Wildcard TLS cert |
| `cloudflare-api-token-secret` | `cert-manager` | Cloudflare DNS-01 token |
| `hetzner-s3-credentials` | `longhorn-system` | S3 backup credentials |
| `tailscale-auth` | `halo` | Headscale subnet router auth key |

---

## Notable Design Decisions

- **Recreate strategy everywhere**: Forced by RWO Longhorn PVCs. Expect a brief downtime on redeploy.
- **Home Assistant node affinity**: The ConBee II Zigbee USB is physically attached to one specific node. HA will not start on any other node.
- **FritzBox as DNS relay (not direct Pi-hole)**: Allows transparent fallback to public DNS if Pi-hole is unreachable, without requiring clients to be reconfigured. Rebind protection exception for `fabseit.net` is required.
- **Headscale `override_local_dns: true`**: With `false`, split DNS rules are silently ignored on most client OSes. The global `9.9.9.9` fallback ensures public DNS still works when away from home.
- **Two VPN options**: WireGuard (full tunnel, routes DNS to Pi-hole via DNAT) and Headscale/Tailscale (overlay, uses split DNS + subnet routing). WireGuard is the simpler/more reliable option for full tunnel access; Headscale is preferred for selective routing.
- **ArgoCD prune disabled**: Prevents accidental deletion of resources when manifests are temporarily removed or reorganised.
