#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "40" "Installing GitLab"

# Namespace
log_info "Creating gitlab namespace"
kubectl create namespace gitlab >/dev/null 2>&1 || log_info "Namespace gitlab already exists"

# Add GitLab repo
log_info "Adding GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

sleep 30

# Low memory configuration optimized for 6GB RAM with controlled resource limits
log_info "Deploying GitLab with Helm (low memory mode)"
log_info "Using custom low-memory configuration with resource limits"
log_info "This may take 30-45 minutes due to resource constraints"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --wait \
  --timeout 45m \
  --wait-for-jobs >/dev/null 2>&1

log_success "GitLab helm chart deployed"

# Wait for webservice ready
log_info "Waiting for GitLab webservice to be operational (up to 20 min)..."

if kubectl -n gitlab rollout status deploy/gitlab-webservice-default --timeout=1200s >/dev/null 2>&1; then
  log_success "GitLab webservice operational"
else
  log_error "GitLab webservice did not respond within expected time, but may be working"
fi

# Credentials and access
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "ERROR_GETTING_PASSWORD")

echo
echo "--------------------------------------------"
echo "            GitLab Access Details           "
echo "--------------------------------------------"
echo "  URL (from VM):  http://localhost:8082     "
echo "  Username:       admin                     "
echo "  Password:       $GITLAB_PASSWORD          "
echo "--------------------------------------------"
