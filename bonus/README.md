# Bonus - DevOps Pipeline with GitLab, ArgoCD and k3d

This directory contains a complete DevOps pipeline implementation using GitLab, ArgoCD and k3d on an Alpine Linux VM.

## Architecture

- **k3d**: Lightweight Kubernetes cluster running in Docker
- **GitLab**: Git repository and CI/CD
- **ArgoCD**: GitOps and automatic deployment
- **Helm**: Application package management
- **Traefik**: Ingress controller and load balancer

## Structure

```
bonus/
├── Vagrantfile                    # VM configuration
├── README.md                      # This file
├── confs/
│   ├── helm-values/               # Helm configurations
│   │   └── argocd-values.yaml     # ArgoCD config
│   ├── charts/
│   │   └── wil42/                 # Application Helm Chart
│   │       ├── Chart.yaml
│   │       ├── values.yaml
│   │       └── templates/
│   │           ├── deployment.yaml
│   │           ├── service.yaml
│   │           ├── ingress.yaml
│   │           ├── NOTES.txt
│   │           └── tests/
│   └── argocd/
│       └── wil42-app.yaml         # ArgoCD Application definition
└── scripts/
    ├── 00_requirements.sh         # Prerequisites installation
    ├── 10_k3d_cluster.sh          # k3d cluster creation
    ├── 20_helm.sh                 # Helm installation
    ├── 30_argocd.sh               # ArgoCD deployment
    ├── 40_gitlab.sh               # GitLab deployment
    ├── 50_app_chart.sh            # Application deployment
    ├── 60_port_forward.sh         # Resilient port-forwards
    ├── logging.sh                 # Logging functions
    └── run.sh                     # Main setup script
```

## Requirements

- VirtualBox
- Vagrant
- 10GB+ available RAM (GitLab is heavy)
- Ports 18081, 18082 and 18083 free on the host

## Usage

### 1. Start VM and automatic setup

```bash
cd bonus
vagrant up
```

This will automatically execute the complete setup (may take 15-20 minutes). The setup will pause and show instructions for GitLab configuration.

### 2. Configure GitLab and upload repository

**Step 2.1: Access GitLab**
- URL: `http://localhost:18082`
- Username: `root`
- Password: Look for GitLab's initial password in the logs

**Step 2.2: Create project in GitLab**
1. Click on "New project" → "Create blank project"
2. Name: `Inception-of-Things` (must match exactly)
3. Mark as **Public**
4. Click "Create project"

**Step 2.3: Upload code from host**
```bash
# From your Mac, in the project directory
cd /Users/enrique/Desktop/42/Inception-of-Things

# Get GitLab password (from the VM)
vagrant ssh -c "kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d"

# Add remote and push
git remote remove origin  # If exists
git remote add gitlab http://root:PASSWORD@localhost:18082/root/inception-of-things.git
git push gitlab
```

### 3. Access services

**Service access (after repo upload):**
- **ArgoCD**: `http://localhost:18081` (admin / holasoyadmin)
- **GitLab**: `http://localhost:18082` (root / password_from_log)
- **Application**: `http://localhost:18083` (once deployed)

### 4. Verify functionality

1. **ArgoCD**: Verify that `wil42` application appears and syncs
2. **Changes**: Modify tag in the chart and push to see GitOps in action  
3. **Port-forwards**: Remain active automatically even if the app is redeployed
4. **Branch**: Make sure you're working on the `master` branch

## DevOps Flow

1. **Developer push** → GitLab receives the code
2. **ArgoCD polling** → Detects changes every 3 minutes (or manual sync)
3. **Auto-sync** → Automatically deploys using Helm
4. **Resilient port-forwards** → Maintain connectivity during redeployments
5. **Monitoring** → ArgoCD monitors application state

### Change application version:
1. Modify `image.tag` in `confs/charts/wil42/values.yaml`
2. Push to internal GitLab on `master` branch
3. Wait 3 minutes or do manual sync in ArgoCD
4. See the new version deployed automatically

## Troubleshooting

### If GitLab doesn't start:
```bash
vagrant ssh
kubectl -n gitlab get pods
kubectl -n gitlab logs deployment/gitlab-webservice-default
```

### If ArgoCD can't access the repo:
- Verify that the GitLab project is **public**
- The repo URL should be: `http://gitlab-webservice-default.gitlab.svc.cluster.local:8181/root/inception-of-things.git`

### If port-forwards don't work:
```bash
vagrant ssh
cd /shared
pkill kubectl  # Stop existing port-forwards
./scripts/60_port_forward.sh  # Restart port-forwards
```

### If the application doesn't deploy:
1. Verify that the repository is uploaded correctly
2. Check Application in ArgoCD UI
3. Do manual sync if necessary

## Cleanup

```bash
vagrant destroy -f
```

## Technical Features

- **OS**: Alpine Linux 3.18
- **Kubernetes**: k3d (k3s in Docker)
- **Container Runtime**: Docker
- **Ingress**: Traefik (included in k3s)
- **Storage**: Local path provisioner
- **DNS**: CoreDNS
- **GitOps**: ArgoCD with polling every 3 minutes
- **Port-forwarding**: Resilient with auto-reconnection

## Implementation Notes

- Idempotent scripts (safe to re-run)
- Resilient port-forwards against redeployments
- Minimal configuration for demo/development
- No persistence (data is lost when destroying VM)
- Optimized for complete GitOps workflow