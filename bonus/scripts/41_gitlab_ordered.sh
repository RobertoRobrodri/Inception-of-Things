#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "40" "Installing GitLab (Phased Deployment for Low Memory)"

# Namespace
log_info "Creating gitlab namespace"
kubectl create namespace gitlab >/dev/null 2>&1 || log_info "Namespace gitlab already exists"

# Add GitLab repo
log_info "Adding GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

sleep 10

# =============================================================================
# FASE 1: INFRASTRUCTURE ONLY (PostgreSQL, Redis, MinIO)
# =============================================================================
log_header "41" "Phase 1: Infrastructure (PostgreSQL, Redis, MinIO)"
log_info "Deploying only database and storage components"
log_info "This minimizes memory usage during initial setup"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=0 \
  --set gitlab.webservice.maxReplicas=0 \
  --set gitlab.sidekiq.minReplicas=0 \
  --set gitlab.sidekiq.maxReplicas=0 \
  --set gitlab.gitaly.replicas=0 \
  --set gitlab.gitlab-shell.minReplicas=0 \
  --set gitlab.gitlab-shell.maxReplicas=0 \
  --set registry.hpa.minReplicas=0 \
  --set registry.hpa.maxReplicas=0 \
  --set gitlab.migrations.enabled=false \
  --timeout 10m \
  --wait >/dev/null 2>&1

log_success "Phase 1 completed: Infrastructure ready"

# Wait for infrastructure to stabilize
log_info "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "PostgreSQL timeout, continuing..."

log_info "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Redis timeout, continuing..."

log_info "Waiting for MinIO to be ready..."
kubectl wait --for=condition=ready pod -l app=minio -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "MinIO timeout, continuing..."

log_success "Infrastructure components operational"
sleep 30

# =============================================================================
# FASE 2: GITALY (Git Repository Storage)
# =============================================================================
log_header "42" "Phase 2: Gitaly (Git Storage)"
log_info "Deploying Gitaly for Git repository storage"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=0 \
  --set gitlab.webservice.maxReplicas=0 \
  --set gitlab.sidekiq.minReplicas=0 \
  --set gitlab.sidekiq.maxReplicas=0 \
  --set gitlab.gitaly.replicas=1 \
  --set gitlab.gitlab-shell.minReplicas=0 \
  --set gitlab.gitlab-shell.maxReplicas=0 \
  --set registry.hpa.minReplicas=0 \
  --set registry.hpa.maxReplicas=0 \
  --set gitlab.migrations.enabled=false \
  --timeout 10m \
  --wait >/dev/null 2>&1

log_success "Phase 2 completed: Gitaly deployed"

log_info "Waiting for Gitaly to be ready..."
kubectl wait --for=condition=ready pod -l app=gitaly -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Gitaly timeout, continuing..."

log_success "Gitaly operational"
sleep 20

# =============================================================================
# FASE 3: MIGRATIONS (Database Setup)
# =============================================================================
log_header "43" "Phase 3: Database Migrations"
log_info "Running database migrations"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=0 \
  --set gitlab.webservice.maxReplicas=0 \
  --set gitlab.sidekiq.minReplicas=0 \
  --set gitlab.sidekiq.maxReplicas=0 \
  --set gitlab.gitaly.replicas=1 \
  --set gitlab.gitlab-shell.minReplicas=0 \
  --set gitlab.gitlab-shell.maxReplicas=0 \
  --set registry.hpa.minReplicas=0 \
  --set registry.hpa.maxReplicas=0 \
  --set gitlab.migrations.enabled=true \
  --timeout 15m \
  --wait \
  --wait-for-jobs >/dev/null 2>&1

log_success "Phase 3 completed: Migrations finished"
sleep 20

# =============================================================================
# FASE 4: SIDEKIQ + GITLAB SHELL (Background Workers)
# =============================================================================
log_header "44" "Phase 4: Sidekiq and GitLab Shell"
log_info "Deploying background workers and SSH gateway"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=0 \
  --set gitlab.webservice.maxReplicas=0 \
  --set gitlab.sidekiq.minReplicas=1 \
  --set gitlab.sidekiq.maxReplicas=1 \
  --set gitlab.gitaly.replicas=1 \
  --set gitlab.gitlab-shell.minReplicas=1 \
  --set gitlab.gitlab-shell.maxReplicas=1 \
  --set registry.hpa.minReplicas=0 \
  --set registry.hpa.maxReplicas=0 \
  --timeout 15m \
  --wait >/dev/null 2>&1

log_success "Phase 4 completed: Sidekiq and GitLab Shell deployed"

log_info "Waiting for Sidekiq to be ready..."
kubectl wait --for=condition=ready pod -l app=sidekiq -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Sidekiq timeout, continuing..."

log_info "Waiting for GitLab Shell to be ready..."
kubectl wait --for=condition=ready pod -l app=gitlab-shell -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "GitLab Shell timeout, continuing..."

log_success "Background workers operational"
sleep 20

# =============================================================================
# FASE 5: WEBSERVICE (Main Application - Most Memory Intensive)
# =============================================================================
log_header "45" "Phase 5: Webservice (Main Application)"
log_info "Deploying GitLab Webservice - this is the most resource-intensive component"
log_warning "This phase may take 10-15 minutes"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=1 \
  --set gitlab.webservice.maxReplicas=1 \
  --set gitlab.sidekiq.minReplicas=1 \
  --set gitlab.sidekiq.maxReplicas=1 \
  --set gitlab.gitaly.replicas=1 \
  --set gitlab.gitlab-shell.minReplicas=1 \
  --set gitlab.gitlab-shell.maxReplicas=1 \
  --set registry.hpa.minReplicas=0 \
  --set registry.hpa.maxReplicas=0 \
  --timeout 20m \
  --wait >/dev/null 2>&1

log_success "Phase 5 completed: Webservice deployed"

log_info "Waiting for GitLab webservice to be operational (up to 15 min)..."
if kubectl -n gitlab rollout status deploy/gitlab-webservice-default --timeout=900s >/dev/null 2>&1; then
  log_success "GitLab webservice operational"
else
  log_warning "GitLab webservice did not respond within expected time, checking status..."
fi

sleep 20

# =============================================================================
# FASE 6: REGISTRY (Optional - Container Registry)
# =============================================================================
log_header "46" "Phase 6: Container Registry (Optional)"
log_info "Deploying Container Registry"
log_info "If memory is tight, you can skip this by pressing Ctrl+C"
sleep 5

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.minReplicas=1 \
  --set gitlab.webservice.maxReplicas=1 \
  --set gitlab.sidekiq.minReplicas=1 \
  --set gitlab.sidekiq.maxReplicas=1 \
  --set gitlab.gitaly.replicas=1 \
  --set gitlab.gitlab-shell.minReplicas=1 \
  --set gitlab.gitlab-shell.maxReplicas=1 \
  --set registry.hpa.minReplicas=1 \
  --set registry.hpa.maxReplicas=1 \
  --timeout 10m \
  --wait >/dev/null 2>&1 || log_warning "Registry deployment had issues, but GitLab core should work"

log_success "GitLab fully deployed (all components)"

# =============================================================================
# VERIFICATION AND CREDENTIALS
# =============================================================================
log_header "47" "Deployment Verification"

log_info "Checking pod status..."
kubectl get pods -n gitlab

log_info "Checking resource usage..."
kubectl top nodes 2>/dev/null || log_warning "Metrics not available"
kubectl top pods -n gitlab 2>/dev/null || log_warning "Pod metrics not available"

# Get password
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "ERROR_GETTING_PASSWORD")

echo
echo "============================================"
echo "       GitLab Deployment Complete!         "
echo "============================================"
echo "  URL (from VM):  http://localhost:8082    "
echo "  Username:       root                     "
echo "  Password:       $GITLAB_PASSWORD         "
echo "============================================"
echo
log_success "GitLab installation completed successfully"