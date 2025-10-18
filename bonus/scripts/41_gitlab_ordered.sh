#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "40" "Installing GitLab (Ordered Deployment)"

# Namespace
log_info "Creating gitlab namespace"
kubectl create namespace gitlab >/dev/null 2>&1 || log_info "Namespace gitlab already exists"

# Add GitLab repo
log_info "Adding GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

sleep 30

# FASE 1: Desplegar solo infraestructura base (PostgreSQL, Redis, MinIO)
log_header "41" "Phase 1: Base Infrastructure (PostgreSQL, Redis, MinIO)"
log_info "Deploying only database and storage components"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --set global.webservice.enabled=false \
  --set global.sidekiq.enabled=false \
  --set global.gitaly.enabled=false \
  --set global.gitlab-shell.enabled=false \
  --set global.migrations.enabled=false \
  --set registry.enabled=false \
  --timeout 10m >/dev/null 2>&1

log_success "Phase 1 completed: Infrastructure ready"

# Esperar a que PostgreSQL esté listo
log_info "Waiting for PostgreSQL to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=postgresql -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "PostgreSQL check timeout, continuing..."

# Esperar a que Redis esté listo
log_info "Waiting for Redis to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=redis -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Redis check timeout, continuing..."

# Esperar a que MinIO esté listo
log_info "Waiting for MinIO to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=minio -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "MinIO check timeout, continuing..."

log_success "Infrastructure components are operational"
sleep 10

# FASE 2: Desplegar Gitaly y Migrations
log_header "42" "Phase 2: Gitaly and Database Migrations"
log_info "Deploying Gitaly and running migrations"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --set global.webservice.enabled=false \
  --set global.sidekiq.enabled=false \
  --set global.gitlab-shell.enabled=false \
  --set registry.enabled=false \
  --timeout 15m \
  --wait-for-jobs >/dev/null 2>&1

log_success "Phase 2 completed: Gitaly and migrations ready"

# Esperar a que Gitaly esté listo
log_info "Waiting for Gitaly to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=gitaly -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Gitaly check timeout, continuing..."

log_success "Gitaly operational"
sleep 10

# FASE 3: Desplegar Sidekiq (background jobs)
log_header "43" "Phase 3: Sidekiq (Background Workers)"
log_info "Deploying Sidekiq workers"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --set global.webservice.enabled=false \
  --set global.gitlab-shell.enabled=false \
  --set registry.enabled=false \
  --timeout 15m >/dev/null 2>&1

log_success "Phase 3 completed: Sidekiq deployed"

# Esperar a que Sidekiq esté listo
log_info "Waiting for Sidekiq to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=sidekiq -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Sidekiq check timeout, continuing..."

log_success "Sidekiq operational"
sleep 10

# FASE 4: Desplegar GitLab Shell
log_header "44" "Phase 4: GitLab Shell"
log_info "Deploying GitLab Shell"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --set global.webservice.enabled=false \
  --set registry.enabled=false \
  --timeout 10m >/dev/null 2>&1

log_success "Phase 4 completed: GitLab Shell deployed"

# Esperar a que GitLab Shell esté listo
log_info "Waiting for GitLab Shell to be ready (up to 10 min)..."
kubectl wait --for=condition=ready pod -l app=gitlab-shell -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "GitLab Shell check timeout, continuing..."

log_success "GitLab Shell operational"
sleep 10

# FASE 5: Desplegar Webservice (el más pesado)
log_header "45" "Phase 5: Webservice (Main Application)"
log_info "Deploying GitLab Webservice (this is the most resource-intensive component)"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --set registry.enabled=false \
  --timeout 20m >/dev/null 2>&1

log_success "Phase 5 completed: Webservice deployed"

# Esperar a que Webservice esté listo
log_info "Waiting for GitLab webservice to be operational (up to 20 min)..."
if kubectl -n gitlab rollout status deploy/gitlab-webservice-default --timeout=1200s >/dev/null 2>&1; then
  log_success "GitLab webservice operational"
else
  log_warning "GitLab webservice did not respond within expected time, but may be working"
fi

sleep 10

# FASE 6: Desplegar Registry (opcional)
log_header "46" "Phase 6: Container Registry (Final Component)"
log_info "Deploying Container Registry"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
  --set global.hosts.domain=localhost \
  --set global.hosts.externalIP=0.0.0.0 \
  --set global.hosts.https=false \
  --set gitlab.migrations.restartPolicy=OnFailure \
  --set gitlab.migrations.backoffLimit=100000 \
  --set global.deployment.restartPolicy=Always \
  --set global.pod.restartPolicy=Always \
  --set gitlab.webservice.deployment.restartPolicy=Always \
  --set gitlab.sidekiq.deployment.restartPolicy=Always \
  --set gitlab.gitaly.deployment.restartPolicy=Always \
  --wait \
  --timeout 30m \
  --wait-for-jobs >/dev/null 2>&1

log_success "GitLab fully deployed (all components)"

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
