# Toolbox for the claude-remote pod. Claude Code itself is NOT baked in: the
# entrypoint installs it onto the home PVC on first start, so it self-updates
# without image rebuilds. Rebuild only to change the tools below.
FROM debian:bookworm-slim

ARG KUBECTL_VERSION=v1.31.5

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq less openssh-client procps ripgrep tini \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/$(dpkg --print-architecture)/kubectl" \
 && chmod 0755 /usr/local/bin/kubectl

RUN useradd --uid 1000 --create-home --home-dir /home/claude --shell /bin/bash claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

USER 1000
ENV HOME=/home/claude \
    PATH=/home/claude/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /home/claude
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
