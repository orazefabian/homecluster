#!/usr/bin/env bash
# One on-demand Claude session (started by the n8n launcher as a Job):
# clone $REPO, pre-trust it, run a single Remote Control session, exit when it
# ends. $HOME is the claude-auth PVC (login + binary); /work is an emptyDir.
#
#   REPO    owner/name on GitHub (required)
#   BRANCH  branch to check out (optional, default: repo default branch)
#   MODE=login  idle instead, for the one-time `claude /login` (bootstrap pod)
set -euo pipefail

if ! command -v claude >/dev/null 2>&1; then
  echo "Installing Claude Code into $HOME/.local/bin ..."
  for i in 1 2 3 4 5; do
    # Leftovers of an interrupted install would eat the small PVC.
    rm -rf "$HOME/.cache/claude/staging" "$HOME"/.local/share/claude/versions/*.tmp.* 2>/dev/null || true
    curl -fsSL https://claude.ai/install.sh | bash && command -v claude >/dev/null && break
    echo "Install attempt $i failed; retrying in 10s"; sleep 10
  done
  command -v claude >/dev/null || { echo "Claude Code install failed" >&2; exit 1; }
fi

if [[ "${MODE:-}" == "login" ]]; then
  echo "Login mode: kubectl exec in and run 'claude', then /login."
  exec sleep infinity
fi

[[ -s "$HOME/.claude/.credentials.json" ]] || {
  echo "Not logged in. Run the bootstrap login pod first (README)." >&2; exit 1; }
[[ "${REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "REPO must be owner/name, got '${REPO:-}'" >&2; exit 1; }

[[ -z "${BRANCH:-}" || "$BRANCH" =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]] || {
  echo "Invalid BRANCH '$BRANCH'" >&2; exit 1; }

name="${REPO#*/}"
dir="/work/$name"

# GitHub: as the GitHub App (README). git and gh fetch short-lived installation
# tokens on demand; commits are authored as <app-slug>[bot].
git_name="Claude (halo)"; git_email="claude-session@halo.fabseit.net"
if [[ -n "${GH_APP_ID:-}" ]]; then
  git config --global credential.https://github.com.helper ghapp
  if gh-app-token >/dev/null; then
    slug=$(curl -fsS -H "Authorization: Bearer $(gh-app-token --jwt)" \
             -H "Accept: application/vnd.github+json" https://api.github.com/app | jq -r .slug)
    uid=$(curl -fsS "https://api.github.com/users/${slug}%5Bbot%5D" | jq -r .id)
    git_name="${slug}[bot]"; git_email="${uid}+${slug}[bot]@users.noreply.github.com"
    echo "GitHub: acting as ${git_name}"
  else
    echo "WARNING: GitHub App token failed; continuing without push access" >&2
  fi
else
  echo "WARNING: no GitHub App configured; continuing without push access" >&2
fi
git config --global user.name  "$git_name"
git config --global user.email "$git_email"

echo "Cloning $REPO${BRANCH:+ ($BRANCH)} ..."
git clone --depth 50 ${BRANCH:+--branch "$BRANCH"} "https://github.com/$REPO.git" "$dir"

# Pre-accept the folder-trust prompt; nobody is at a terminal to answer it.
cfg="$HOME/.claude.json"
[[ -s "$cfg" ]] || echo '{}' > "$cfg"
tmp="$(mktemp)"
jq --arg d "$dir" '.projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted: true})' "$cfg" > "$tmp"
mv "$tmp" "$cfg"

cd "$dir"
echo "Starting Remote Control session '$name' (mode: ${SESSION_MODE:-standard}) ..."
# --spawn session: exactly one session; the process exits when it ends, and
# with it the pod and (via ttlSecondsAfterFinished) the Job.
exec claude remote-control \
  --spawn session \
  --name "${SESSION_MODE:-standard}: $name" \
  ${CLAUDE_RC_EXTRA_ARGS:-}
