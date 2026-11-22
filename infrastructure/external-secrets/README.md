# External Secrets (Vaultwarden → k8s Secrets)

Vaultwarden is the source of truth for every hand-made Secret in the cluster.
[External Secrets Operator](https://external-secrets.io) (ESO) reads items from
it and writes them into ordinary k8s Secrets. Apps don't change: they keep
reading the same Secret names.

```
Bitwarden app ──edit──▶ Vaultwarden (halo/bitwarden; PVC backed up to NFS + Hetzner S3)
                              ▲ https://bitwarden.halo.fabseit.net (pinned to 192.168.8.30)
                  bitwarden-cli  (`bw serve`, ns external-secrets, NetworkPolicy: ESO only)
                              ▲ http :8087 /object/item/<id>
                  ESO controller ── ClusterSecretStores bitwarden-fields / -login / -notes
                              │
                  ExternalSecret (in git, next to the app) ──▶ Secret
```

| Path | What |
|---|---|
| `Chart.yaml`, `values.yaml` | ESO itself (ArgoCD app `external-secrets-helm`, vendored chart) |
| `manifests/bitwarden-cli.yaml` | The `bw serve` bridge, logged in as the read-only `k8s` account. Image: [`ghcr.io/charlesthomas/bitwarden-cli`](https://github.com/charlesthomas/bitwarden-cli), a community build of ESO's documented Dockerfile (Bitwarden has no official one), pinned by digest |
| `manifests/networkpolicy.yaml` | Only ESO may reach the bridge. `bw serve` has **no auth** |
| `manifests/clustersecretstores.yaml` | The three webhook stores |
| `manifests/prometheusrule.yaml` | Alerts: sync failing, store not ready, bridge down |

## Conventions

- **One Vaultwarden item per k8s Secret**, in org `homecluster` → collection `homecluster`.
  The item is named `<namespace>/<secret>` and holds **one hidden custom field per Secret key**, named exactly like the key.
- ExternalSecrets reference the item by **ID** (the `itemId=` in the web vault URL), so renaming an item breaks nothing.
- Multi-line values (config files) go in the item's **notes** and use the `bitwarden-notes` store, with one key per item.
- Every ExternalSecret uses `creationPolicy: CreateOrMerge`. It creates the Secret if missing, never deletes it
  (not even when the ExternalSecret is removed or pruned), and leaves keys it doesn't manage alone.
  That last part matters for Secrets that other software also writes to (`tailscale-auth`).
- **Always set `target.template.metadata`** (with the two ArgoCD annotations from the template below).
  Without it, ESO copies the ExternalSecret's labels onto the Secret, including ArgoCD's
  `app.kubernetes.io/instance` tracking label. ArgoCD then treats the Secret as its own resource that
  isn't in git, and auto-prune **deletes it** on the next sync. The annotations are a second safeguard:
  never prune it, and ignore it when comparing.
- `refreshInterval: 15m` (17 small requests per 15 min against the in-cluster bridge; negligible). The bridge pulls from Vaultwarden every 2 minutes (its liveness probe POSTs `/sync`). If Vaultwarden or the bridge is down,
  Secrets simply stop updating. Running apps are unaffected.
- To have a value changed in Vaultwarden roll the pod automatically, put `reloader.stakater.com/auto: "true"`
  in the Deployment's **metadata** annotations. Use it for API keys and tokens. **Don't** use it for
  database passwords: changing one in Vaultwarden doesn't change it inside Postgres. Rotate those by hand
  (`ALTER USER`, then the Vaultwarden field, then restart the app).

## One-time setup

1. **Vaultwarden** (web vault):
   - Register a dedicated account, e.g. `k8s@fabseit.net`, with a long random master password.
   - With your own account, create the org `homecluster` and the collection `homecluster`. Invite the `k8s` account
     and give it **Can view** on that collection only. Don't use "Can view, except passwords", because hidden
     fields would come back masked.
   - Log in as `k8s` → Settings → Security → Keys → **View API key** (`client_id` / `client_secret`).
   - Save all three values in **your personal vault** (item `homecluster/bootstrap: bitwarden-cli`).
2. **Bootstrap secret.** This is the only hand-applied Secret in normal operation:
   ```sh
   kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n external-secrets create secret generic bitwarden-cli \
     --from-literal=BW_CLIENTID='user.xxxxxxxx-...' \
     --from-literal=BW_CLIENTSECRET='...' \
     --from-literal=BW_PASSWORD='...'
   ```
3. **ArgoCD.** `external-secrets-helm` installs the CRDs. If the `external-secrets` app synced first and
   failed on the ClusterSecretStores, sync it once more by hand.
4. **Check it:**
   ```sh
   kubectl -n external-secrets get pods                 # bitwarden-cli 1/1 Ready = logged in + unlocked
   kubectl get clustersecretstores                      # all three Ready
   ```

## Adding a Secret

1. In the Bitwarden app, create an item (secure note) named `<namespace>/<secret>` in the `homecluster`
   collection. Add one **hidden** custom field per Secret key, named exactly like the key.
2. Copy its item ID from the web vault URL (`...&itemId=<uuid>`).
3. Commit an `externalsecret.yaml` next to the app's manifests:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: pihole-secret
  namespace: halo
spec:
  refreshInterval: 15m
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-fields
  target:
    name: pihole-secret
    creationPolicy: CreateOrMerge
    template:                                    # REQUIRED, see Conventions
      # type: kubernetes.io/dockerconfigjson     # only for non-Opaque Secrets
      metadata:
        annotations:
          argocd.argoproj.io/sync-options: Prune=false
          argocd.argoproj.io/compare-options: IgnoreExtraneous
  data:
    - secretKey: WEBPASSWORD                     # key in the k8s Secret
      remoteRef:
        key: <item-id>
        property: WEBPASSWORD                    # custom field name in the item
```

4. Check `kubectl -n <ns> get externalsecret <name>` shows `SecretSynced`.

Special cases:

| Secret | How |
|---|---|
| Multi-line value (`halo/wireguard`'s `wg0.conf.template`) | Put it in the item's **notes**. Use store `bitwarden-notes` and omit `property` |
| `halo/tailscale-auth` | Sync only `TS_AUTHKEY`. Tailscale writes its own state keys into this Secret; CreateOrMerge leaves them alone |
| `halo/regcred` | Single field `.dockerconfigjson`, plus `template.type: kubernetes.io/dockerconfigjson` |
| `metallb-system/memberlist` | Works like any other. Losing it stops all MetalLB speakers, so having it in Vaultwarden is the point |

The initial migration of the existing hand-made Secrets used a one-off local script, not kept in the repo.
It copied each live Secret into an item and printed the ExternalSecret. ESO's write changed no values,
so no pod restarted.

**Not managed here** (controllers generate these, or they're legacy): cert-manager TLS secrets and the ACME
account key (`cert-manager/cloudflare-api-key-secret`), webhook CAs/certs, Helm release / Prometheus /
Grafana / Alertmanager secrets, ArgoCD's own secrets, k3s node passwords, `dynatrace-*`, and everything
in `default` (legacy, #93).

## Day to day

- **Change a value:** edit the field in the Bitwarden app. It lands within about 17 minutes at most (bridge sync up to 2 min + refresh up to 15 min). To get it in now:
  `kubectl -n <ns> annotate externalsecret <name> force-sync=$(date +%s) --overwrite`
  (the bridge syncs every 2 min. To skip that wait, restart it: `kubectl -n external-secrets rollout restart deploy/bitwarden-cli`).
- **New Secret:** see "Adding a Secret" above.
- **Rotate the k8s account's API key or password:** update the `bitwarden-cli` Secret. Reloader restarts the bridge.
- **Upgrade the CLI:** Renovate bumps the bridge image's tag and digest. This container holds the `k8s`
  account's master password, so look at the upstream repo's diff before merging.

## Disaster recovery (whole cluster lost)

Vaultwarden runs inside the cluster, so it has to come back before anything else can get its secrets.
Your Bitwarden desktop/mobile apps keep an offline copy of the vault, so the values below stay readable
while the cluster is down.

1. k3s → ArgoCD → MetalLB, ingress-nginx, Longhorn (none of these need synced secrets).
2. Hand-apply what Vaultwarden's own restore path needs (values from your Bitwarden app):
   - `cert-manager/cloudflare-api-token-secret`: without it there's no wildcard cert, ingress serves a
     self-signed cert, and the bridge (which requires HTTPS) can't log in.
   - `longhorn-system/hetzner-s3-credentials`: only if restoring from S3 because the NFS backups on halo-8 are gone too.
3. Restore `bitwarden-pvc` from the latest Longhorn backup (NFS, otherwise S3) and let `bitwarden-app` start.
4. Apply `external-secrets/bitwarden-cli` (step 2 of the one-time setup). ESO now fills in every other Secret.
   The hand-applied ones from step 2 are taken over seamlessly (CreateOrMerge).

As an extra safeguard, now and then store an encrypted export somewhere off-cluster:
`bw export --organizationid <homecluster org id> --format encrypted_json`.

## Troubleshooting

- **Bridge not Ready:** `kubectl -n external-secrets logs deploy/bitwarden-cli`. Usual causes: wrong API key or
  password in the bootstrap Secret, Vaultwarden down, or the wildcard cert missing or invalid.
- **`SecretSyncedError`:** `kubectl describe externalsecret ...`. Usual causes: the item isn't in the
  `homecluster` collection (the `k8s` account can't see it), a typo in the item ID or field name, or the
  field was added after the bridge's last sync (wait up to 2 min).
- **403 from the bridge:** it must run `bw serve --hostname all`. With `0.0.0.0`, CLI ≥ 2026.6.0 rejects
  requests addressed to the Service name.
