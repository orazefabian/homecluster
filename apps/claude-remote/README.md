# claude-remote: on-demand Claude Code sessions

Start a Claude Code session on the cluster for any allowlisted repo, drive it from claude.ai/code or the
Claude app, and have it vanish again when you're done. **Nothing runs while idle.**

```
Homepage "Claude session" ─► n8n form (/form/claude-session, n8n login)
   └─► n8n creates Job in claude-sessions ─► pod clones repo, pre-trusts it,
       runs `claude remote-control --spawn session` ─► session shows up at claude.ai/code
   session ends ─► process exits ─► pod Completed ─► Job deleted after 120 s
```

claude.ai cannot start anything on the cluster itself: Remote Control only lists sessions from a
`claude` process that's already running. That's why the n8n form exists.

- **One session at a time.** The login PVC is RWO, and the form refuses a second Start.
- **Lifetime:** until the session ends, or **Action = Stop** in the form, or 8 h (`activeDeadlineSeconds`).
- **Nothing persists except the login.** The repo lives in an `emptyDir`, so unpushed work is lost with
  the pod. Push a branch or open a PR.
- **Tools:** Node 22 (npm, pnpm and yarn via corepack), Python 3 (pip, venv), build-essential, git, gh,
  kubectl, jq, ripgrep. There's no Docker, so images build in GitHub Actions. Memory limit 4 Gi.

## Modes

| | standard (`claude-session`) | privileged (`claude-session-admin`) |
|---|---|---|
| Read cluster-wide | yes, except Secrets | yes, except Secrets |
| `halo` | read | create/modify/delete workloads, Services, Ingresses, ConfigMaps, PVCs, Jobs; exec, logs, port-forward; create Secrets (never read them) |
| `monitoring` | read | ConfigMaps (dashboards), PrometheusRules, Service/PodMonitors, AlertmanagerConfigs |
| GitHub | push branches, open PRs (never main) | same |

**What privileged mode must never do: delete Longhorn backups.** These layers enforce it:

1. **RBAC** (`manifests/rbac-admin.yaml`) never grants:
   - anything in `longhorn-system`, `argocd`, `external-secrets` or `kube-system`
   - writes to `longhorn.io`, `external-secrets.io` or `argoproj.io`
   - writes to RBAC or admission policies
   - cluster-scoped writes
   - endpoints
   - SA tokens
   - reading Secrets
2. **ValidatingAdmissionPolicies** (`manifests/admission-policy.yaml`) apply only to the privileged SA. They
   deny:
   - privileged, hostPath/NFS/iSCSI and host-namespace pods (direct or in any workload template)
   - the `halo/admin-user` cluster-admin SA and its token Secret
   - exec into Home Assistant, WireGuard or the subnet router
   - ExternalName Services and nginx snippet annotations

   Because of this, privileged mode can't edit the HA, WireGuard or subnet-router Deployments. Do those
   through a PR.
3. **The Longhorn API is closed for everyone** (`infrastructure/longhorn/manifests/networkpolicy-api.yaml`).
   `longhorn-manager:9500` only accepts `longhorn-system` and Prometheus, and `longhorn-ui` only accepts
   ingress-nginx. The UI sits behind basic auth.

Known residual risks (in-cluster guardrails only, no off-cluster lock):
- A workload in `halo` could talk NFS to halo-8 directly if its exports allow unprivileged source ports
  (`insecure`).
- Whatever Vaultwarden or GitHub allows from outside the cluster.

If `halo/admin-user` (cluster-admin, hand-made in 2025) is no longer needed, delete it. It's the most
dangerous object any `halo` workload can reach.

## GitHub access

Both modes push with **your fine-grained PAT** (Vaultwarden `claude-sessions/claude-session` → `GH_TOKEN`):
- only the repos offered in the form
- Contents + Pull requests read/write, nothing else (no Administration, so it can't change rulesets)

Each offered repo has a ruleset on `main`: require a pull request, **no bypass actors**. Sessions can
push branches and open PRs, but never push to main. The ruleset applies to you too.

Trade-off: the token acts as you, so a session **can merge its own PR**, and ArgoCD would then deploy
it. PRs and pushes show up as yours. Commits are authored as `Claude (halo)`. To make merging
impossible, move to a GitHub App with a required approval (see the PR #151 discussion).

## Setup (once)

1. **GitHub:**
   - Create a fine-grained PAT: resource owner you, the offered repos only, Contents + Pull requests
     read/write.
   - Put it in Vaultwarden item `claude-sessions/claude-session`, hidden field `GH_TOKEN`, and put the
     item ID in `manifests/externalsecret.yaml`.
   - On each repo, add a ruleset for `main`: require a pull request, no bypass list.
2. **Longhorn UI auth:**
   - Run `htpasswd -nB admin` and put the whole output line in Vaultwarden item
     `longhorn-system/longhorn-ui-auth`, hidden field `auth`. The item ID is already in
     `infrastructure/longhorn/manifests/externalsecret-ui-auth.yaml`.
   - Until the Secret exists, ingress-nginx answers the Longhorn host with 503.
3. **Image:** after the first push to main builds it, set the ghcr package
   `homecluster/claude-remote` to **public**. There's no pull secret.
4. **Claude login:**
   ```sh
   kubectl apply -f apps/claude-remote/bootstrap/login-pod.yaml
   kubectl -n claude-sessions exec -it claude-login -- claude auth login   # follow the URL
   kubectl -n claude-sessions delete pod claude-login
   ```
   Repeat this when sessions fail with "Not logged in" or "You must be logged in".
5. **n8n:**
   - Import `n8n/claude-launcher.workflow.json`.
   - Create an *HTTP Header Auth* credential named `k8s claude-launcher`: header `Authorization`, value
     `Bearer <token>`. Get the token from
     `kubectl -n claude-sessions get secret n8n-claude-launcher-token -o jsonpath='{.data.token}' | base64 -d`.
   - Select the credential in the three HTTP nodes and activate the workflow.
   - The form uses **n8n User Auth**, so only logged-in n8n users can open it, even though n8n is also
     public at `n8n.fabseit.net`.

## Day to day

- **Add a repo:**
  - add it to the form's Repository dropdown **and** to `REPOS` in the Decide node
  - add the repo to the PAT and add the ruleset
  - re-export the workflow into `n8n/`
- **Logs:** `kubectl -n claude-sessions logs job/<name>`. Failed Jobs also disappear after 120 s. To
  debug, raise `ttlSecondsAfterFinished` in the Decide node.
- **Update the tools:** edit `image/`, then bump `IMAGE_TAG` in `.github/workflows/claude-remote-image.yml`,
  the `IMAGE` constant in the Decide node, and `bootstrap/login-pod.yaml` together. Claude Code itself
  updates itself on the PVC.
- **Revoke everything:** remove the device in claude.ai settings, revoke the PAT, and delete the Job.
