# Architecture diagrams

Interactive cluster diagrams served at `architecture.halo.fabseit.net` by a
plain nginx pod. Each page lives in its own ConfigMap (see
`manifests/kustomization.yaml`).

| Path | What |
|------|------|
| `source/*.architecture.json` | Diagram sources (Archify architecture schema) |
| `manifests/site/*.html` | Rendered pages, committed as-is |
| `manifests/site/index.html` | Hand-written tab shell that iframes the pages |

## Updating a diagram

Edit the JSON in `source/`, then render it into `manifests/site/` with the
Archify skill:

```bash
node bin/archify.mjs deliver architecture \
  apps/architecture/source/network.architecture.json \
  apps/architecture/manifests/site/network.html --quality showcase
```

Source → page mapping: `homecluster` → `homecluster-architecture.html`, the
others keep their name (`network` → `network.html`, …). Commit both files;
the ConfigMap hash changes and ArgoCD rolls the pod.

Keep each page under 1 MiB (ConfigMap limit).
