# 🏠 HomeCluster Repository

Welcome to the **HomeCluster** repository! 🎉 This repo contains all the Kubernetes object definitions for managing my home cluster. It's designed to be a single source of truth, leveraging **ArgoCD** for GitOps-style synchronization. 🚀

---

## 📚 **Overview**

This repository is structured to manage both **applications** and **infrastructure components** in my home Kubernetes cluster. Using ArgoCD, the cluster stays in sync with this repo, ensuring a declarative and automated deployment process. 🛠️

### ✨ Features
- **GitOps with ArgoCD**: Automated syncing of cluster resources from this repository. 🔄
- **Declarative Configurations**: YAML manifests for all applications and infrastructure components. 📜
- **Namespace Isolation**: Applications are neatly organized into namespaces for better management. 🗂️
- **Self-Healing Deployments**: ArgoCD ensures that any drift from the desired state is corrected automatically. ❤️‍🩹

---

## 🗂️ **Repository Structure**

Here's how the repo is organized:

```
.
├── apps/
│   ├── ddclient/
│   ├── heimdall/
│   ├── uptime-kuma/
│   ├── pihole/
│   ├── bitwarden/
│   ├── samba-share/
│   ├── wireguard/
│   ├── headscale/
│   ├── homeassistant/
│   ├── paperless/
│   │   ├── postgresdb/
│   │   ├── redis/
│   │   ├── webservice/
│   ├── speedtest/
│   ├── n8n/
│   │   ├── postgresdb/
│   │   ├── webservice/
│   ├── immich/
│   │   ├── app/
│   │   ├── postgres/
│   │   ├── redis/
├── infrastructure/
│   ├── argocd/
│   ├── longhorn/
│   ├── cert-manager/
│   ├── metallb/
│   ├── ingress-nginx/
│   ├── secets-backup/
│   ├── reloader/
│   ├── kite/
└── argocd-bootstrap.yaml
```

### 🔑 Key Components:
1. **Applications** (`apps/`):
    - `ddclient`: Dynamically update DNS entries. 🔃
    - `heimdall`: Dashboard for all sorts of services. 📊
    - `uptime-kuma`: Uptime monitoring tool. ✅
    - `pihole`: DNS sinkhole for ad blocking. 🚫
    - `bitwarden`: Secure password management. 🔐
    - `samba-share`: File sharing made simple. 📁
    - `wireguard`: VPN solution for secure connectivity. 🔒
    - `headscale`: Open-source Tailscale control server for split-tunnel VPN access. 🌐
    - `homeassistant`: Automate your smart home devices! 🏡
    - `paperless`: Store and search your documents effectively. 📝
    - `speedtest`: Test your internet speed. 🚀
    - `n8n`: Workflow automations for days!. 🛠️
    - `immich`: Self hosted images solution. 📸

2. **Infrastructure** (`infrastructure/`):
    - `argocd`: ArgoCD configuration with separate ApplicationSets for Helm charts and manifests. 🔄
    - `longhorn`: Distributed block storage for Kubernetes (deployed via Helm). 📦
    - `cert-manager`: Automated TLS certificate management (deployed via Helm). 🔑
    - `metallb`: Load balancer for bare-metal clusters. ⚖️
    - `ingress-nginx`: HTTP and HTTPS routing for services (deployed via Helm). 🌍
    - `secrets-backup`: Custom backup solution for k8s secrets. 📥
    - `reloader`: Make your pods reload on secrets or configmap changes. ⟳
    - `kite`: Modern k8s dashboard.

3. **ArgoCD Bootstrap Configuration** (`argocd-bootstrap.yaml`):
    This file defines a bootstrap Application that monitors the `infrastructure/argocd` directory, enabling ArgoCD to manage its own configuration updates automatically.

---

## 🚀 **Getting Started**

### 1️⃣ Clone the Repository:
```bash
git clone https://github.com/orazefabian/homecluster.git
cd homecluster
```

### 2️⃣ Install ArgoCD:
Follow the [official ArgoCD installation guide](https://argo-cd.readthedocs.io/en/stable/getting_started/).

### 3️⃣ Apply the ArgoCD Bootstrap Application:
```bash
kubectl apply -f argocd-bootstrap.yaml
```
This will set up ArgoCD to monitor and sync all applications and infrastructure, including its own configuration.

### 4️⃣ Watch the Magic! ✨
ArgoCD will automatically sync the resources defined in this repository to your cluster.

---

## ⚙️ **ArgoCD Sync Policy**

The sync policy is configured as follows:
- **Automated Sync**: Resources are automatically applied to the cluster.
- **Self-Healing**: Any drift from the desired state is corrected.
- **Namespace Creation**: Namespaces are created automatically if they don't exist.

---

## 📊 Status Monitoring

Use the ArgoCD UI to monitor application health and sync status:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access the UI at [https://localhost:8080](https://localhost:8080). 🎨

---


## 📄 License

This project is licensed under the MIT License.

---

Made with ❤️ and Kubernetes 🧩 by [orazefabian](https://github.com/orazefabian).
