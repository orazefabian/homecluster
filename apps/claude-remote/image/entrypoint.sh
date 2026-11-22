#!/usr/bin/env bash
# Starts `claude remote-control` in $WORKDIR. Until the one-time bootstrap
# (login + clone + trust, see apps/claude-remote/README.md) is done it idles
# instead of crash-looping, so you can `kubectl exec` in and finish it.
set -euo pipefail

WORKDIR="${CLAUDE_WORKDIR:-$HOME/homecluster-helm}"

if ! command -v claude >/dev/null 2>&1; then
  echo "Installing Claude Code into $HOME/.local/bin ..."
  for i in 1 2 3 4 5; do
    curl -fsSL https://claude.ai/install.sh | bash && command -v claude >/dev/null && break
    echo "Install attempt $i failed; retrying in 10s"; sleep 10
  done
  command -v claude >/dev/null || { echo "Claude Code install failed" >&2; exit 1; }
fi

# gh uses GH_TOKEN directly; also let plain `git push` over https use it.
if [[ -n "${GH_TOKEN:-}" ]]; then
  git config --global credential.https://github.com.helper '!gh auth git-credential'
fi

if [[ ! -s "$HOME/.claude/.credentials.json" || ! -d "$WORKDIR/.git" ]]; then
  echo "Not bootstrapped yet (need login and a clone at $WORKDIR). Idling; see README."
  exec sleep infinity
fi

cd "$WORKDIR"
exec claude remote-control \
  --name "${CLAUDE_RC_NAME:-halo}" \
  --spawn "${CLAUDE_RC_SPAWN:-worktree}" \
  ${CLAUDE_RC_EXTRA_ARGS:-}
