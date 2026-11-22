# Toolbox for on-demand Claude sessions (apps/claude-remote/README.md).
# Node 22 + npm/pnpm/yarn (corepack), Python 3, build tools, git, gh, kubectl.
# Claude Code itself is NOT baked in: the entrypoint installs it onto the auth
# PVC on first start, so it self-updates without image rebuilds. Package
# caches go to /work (the session's emptyDir), not the small auth PVC.
FROM node:22-bookworm-slim

ARG KUBECTL_VERSION=v1.31.5

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git jq less openssh-client procps \
      python3 python3-pip python3-venv ripgrep tini unzip \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl" \
 && chmod 0755 /usr/local/bin/kubectl \
 && corepack enable

# The node image already has uid 1000 ("node"); rename it.
RUN usermod -l claude -d /home/claude -m node && groupmod -n claude node \
 && install -d -o 1000 -g 1000 /work

COPY entrypoint.sh gh-app-token git-credential-ghapp gh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/gh-app-token \
      /usr/local/bin/git-credential-ghapp /usr/local/bin/gh

USER 1000
ENV HOME=/home/claude \
    COREPACK_HOME=/home/claude/.cache/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    npm_config_cache=/work/.cache/npm \
    PIP_CACHE_DIR=/work/.cache/pip \
    PATH=/home/claude/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
