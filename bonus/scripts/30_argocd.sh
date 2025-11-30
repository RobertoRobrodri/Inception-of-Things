#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "30" "Installing ArgoCD"

# Namespace
log_info "Creating argocd namespace"
kubectl create namespace argocd >/dev/null 2>&1 || log_info "Namespace argocd already exists"

# Add ArgoCD repo
log_info "Adding ArgoCD Helm repository"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Values with Traefik Ingress
VALUES="/shared/confs/helm-values/argocd-values.yaml"
log_info "Deploying ArgoCD with Helm"
log_info "Using values: ${VALUES}"

helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f "${VALUES}" >/dev/null 2>&1

log_success "ArgoCD deployed successfully"

# Wait for server ready
log_info "Waiting for ArgoCD server to be ready (up to 10 min)..."

if kubectl -n argocd rollout status deploy/argocd-server --timeout=600s >/dev/null 2>&1; then
  log_success "ArgoCD server operational"
else
  log_error "ArgoCD server did not respond within expected time"
fi

# Credentials and access
echo
echo "--------------------------------------------"
echo "            ArgoCD Access Details           "
echo "--------------------------------------------"
echo "  URL (from VM):  http://localhost:8081     "
echo "  Username:       admin                     "
echo "  Password:       holasoyadmin              "
echo "--------------------------------------------"
