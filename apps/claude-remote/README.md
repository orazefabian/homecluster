# claude-remote

Runs `claude remote-control` in a pod, so you can start and drive Claude Code sessions on the cluster
from claude.ai/code or the Claude mobile app. Claude runs here, and claude.ai only shows the session.
The server shows up as **halo** in the session list. Each new session started from the web gets its
own git worktree of `~/homecluster-helm` (`--spawn worktree`).

## What it can do

| | |
|---|---|
| Kubernetes | Read-only, cluster-wide, **no Secrets**, no exec or port-forward (`rbac.yaml`: built-in `view` + `claude-remote-extra-read`). |
| GitHub | `GH_TOKEN`: fine-grained PAT for this repo only (Contents + Pull requests: read/write). `main` is protected, so changes land through a PR and ArgoCD. |
| Network | Egress open (Anthropic, GitHub, LAN). No ingress (NetworkPolicy), no Service. |

## Files

- `image/`: the toolbox image (git, gh, kubectl, jq, ripgrep), built for arm64 by
  `.github/workflows/claude-remote-image.yml` → `ghcr.io/orazefabian/homecluster/claude-remote`.
  Claude Code itself isn't in the image: the entrypoint installs it onto the PVC on first start, and it
  updates itself from there. To change the tools, bump `IMAGE_TAG` in the workflow and the tag in
  `manifests/deployment.yaml` together.
- `manifests/`: Deployment (`Recreate`, not on halo-0, prefers halo-1/halo-2), PVC `claude-remote-home`
  (mounted as `$HOME`, `default` backup group), RBAC, ExternalSecret, NetworkPolicy.

## One-time bootstrap

Until this is done, the pod idles (`Not bootstrapped yet` in the log) instead of crash-looping.

1. Create Vaultwarden item `halo/claude-remote` with a hidden field `GH_TOKEN` and put its item ID in
   `manifests/externalsecret.yaml`. The pod also starts without it; you just get no `gh`/push.
2. Log in with a Claude subscription account, clone the repo and trust the folder:
   ```sh
   kubectl -n halo exec -it deploy/claude-remote -- bash
   claude                      # then /login, follow the URL, paste the code, /exit
   git clone https://github.com/orazefabian/homecluster.git ~/homecluster-helm
   git -C ~/homecluster-helm config user.name  "<name>"
   git -C ~/homecluster-helm config user.email "<email>"
   cd ~/homecluster-helm && claude   # answer the folder-trust prompt, then /exit
   exit
   kubectl -n halo delete pod -l app=claude-remote
   ```
3. `kubectl -n halo logs deploy/claude-remote` should show Remote Control running, and **halo** shows
   up at claude.ai/code.

The login token lives in `~/.claude/.credentials.json` on the PVC, so it's in Longhorn backups too.
To revoke it, remove the device or session in your claude.ai account settings.

## Day to day

- Sessions started from the web prompt for permissions there (default permission mode). To change the
  mode for new sessions, set env `CLAUDE_RC_EXTRA_ARGS`, e.g. `--permission-mode acceptEdits`.
- Restarting the pod ends running sessions. The worktrees and history stay on the PVC.
- Stale worktrees pile up under `~/homecluster-helm`. Clean them with `git worktree prune` or `git worktree remove`.
