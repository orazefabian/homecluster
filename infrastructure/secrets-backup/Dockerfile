FROM python:3.11-alpine

# Install kubectl with proper architecture detection
RUN apk add --no-cache curl && \
    ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then KUBECTL_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then KUBECTL_ARCH="arm64"; \
    elif [ "$ARCH" = "armv7l" ]; then KUBECTL_ARCH="arm"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBECTL_ARCH}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Python dependencies
RUN pip install PyYAML

# Create app directory
WORKDIR /app

# Copy backup script
COPY backup_secrets_k8s.py /app/backup_secrets.py

# Create backup user and directory
RUN adduser -D -s /bin/sh backup && \
    mkdir -p /backup && \
    chown backup:backup /backup

USER backup

# Default command
CMD ["python", "/app/backup_secrets.py", "/backup"]