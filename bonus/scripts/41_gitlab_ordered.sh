#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "40" "Installing GitLab (Phased Deployment for Low Memory)"

# =============================================================================
# PASO 0: VERIFICAR Y CREAR SWAP SI ES NECESARIO
# =============================================================================
log_header "39" "Memory Check and Swap Configuration"

# Mostrar memoria actual
log_info "Current memory status:"
free -h

# Verificar si ya existe swap
SWAP_SIZE=$(free -h | grep Swap | awk '{print $2}')
if [ "$SWAP_SIZE" = "0B" ] || [ "$SWAP_SIZE" = "0" ]; then
    log_warning "No swap detected. Creating 2GB swap file for safety..."
    
    if [ -f /swapfile ]; then
        log_info "Swap file already exists, activating it..."
        sudo swapon /swapfile 2>/dev/null || log_warning "Could not activate existing swapfile"
    else
        log_info "Creating 2GB swap file (this may take 1-2 minutes)..."
        
        if sudo fallocate -l 2G /swapfile 2>/dev/null; then
            log_success "Swap file created successfully"
        else
            log_warning "fallocate failed, trying dd command (slower)..."
            sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress 2>/dev/null || {
                log_error "Failed to create swap file"
                log_warning "Continuing without swap (risky)"
                sleep 3
            }
        fi
        
        if [ -f /swapfile ]; then
            log_info "Configuring swap file..."
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile >/dev/null 2>&1
            sudo swapon /swapfile 2>/dev/null || log_warning "Could not activate swap"
            
            if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
                log_info "Adding swap to /etc/fstab for persistence..."
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
                log_success "Swap configured to persist across reboots"
            fi
        fi
    fi
    
    echo ""
    log_info "Memory status after swap configuration:"
    free -h
    echo ""
    
    SWAP_ACTIVE=$(free -h | grep Swap | awk '{print $2}')
    if [ "$SWAP_ACTIVE" != "0B" ] && [ "$SWAP_ACTIVE" != "0" ]; then
        log_success "Swap is now active: $SWAP_ACTIVE"
    else
        log_warning "Swap could not be activated. Deployment will proceed but is risky."
        sleep 5
    fi
else
    log_success "Swap already configured: $SWAP_SIZE"
    free -h
fi

echo ""
sleep 5

# =============================================================================
# PASO 1: KUBERNETES SETUP
# =============================================================================
log_info "Creating gitlab namespace"
kubectl create namespace gitlab >/dev/null 2>&1 || log_info "Namespace gitlab already exists"

log_info "Adding GitLab Helm repository"
helm repo add gitlab https://charts.gitlab.io/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

sleep 10

# =============================================================================
# FASE 1: INFRASTRUCTURE + GITALY
# =============================================================================
log_header "41" "Phase 1: Infrastructure + Gitaly"
log_info "Deploying database, storage, and Gitaly"
log_info "Memory usage will be ~2-2.5GB in this phase"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.enabled=false \
  --set gitlab.sidekiq.enabled=false \
  --set gitlab.gitlab-shell.enabled=false \
  --set registry.enabled=false \
  --set gitlab.migrations.enabled=false \
  --timeout 15m \
  --wait >/dev/null 2>&1

log_success "Phase 1 helm deployment completed"

# Esperar con labels correctas
log_info "Waiting for PostgreSQL..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "PostgreSQL timeout, continuing..."

log_info "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Redis timeout, continuing..."

log_info "Waiting for MinIO..."
kubectl wait --for=condition=ready pod -l app=minio -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "MinIO timeout, continuing..."

log_info "Waiting for Gitaly..."
kubectl wait --for=condition=ready pod -l app=gitaly -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Gitaly timeout, continuing..."

log_success "All infrastructure components operational"

log_info "Current memory usage:"
free -h | grep -E "Mem:|Swap:"
echo ""

sleep 30

# =============================================================================
# FASE 2: MIGRATIONS
# =============================================================================
log_header "42" "Phase 2: Database Migrations"
log_info "Running database migrations (this may take 10-15 minutes)"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.enabled=false \
  --set gitlab.sidekiq.enabled=false \
  --set gitlab.gitlab-shell.enabled=false \
  --set registry.enabled=false \
  --set gitlab.migrations.enabled=true \
  --timeout 20m \
  --wait \
  --wait-for-jobs >/dev/null 2>&1

log_success "Phase 2 completed: Migrations finished"

log_info "Memory usage after migrations:"
free -h | grep -E "Mem:|Swap:"
echo ""

sleep 20

# =============================================================================
# FASE 3: SIDEKIQ + GITLAB SHELL
# =============================================================================
log_header "43" "Phase 3: Sidekiq and GitLab Shell"
log_info "Deploying background workers and SSH gateway"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.enabled=false \
  --set gitlab.sidekiq.enabled=true \
  --set gitlab.gitlab-shell.enabled=true \
  --set registry.enabled=false \
  --timeout 15m \
  --wait >/dev/null 2>&1

log_success "Phase 3 completed: Workers deployed"

log_info "Waiting for Sidekiq..."
kubectl wait --for=condition=ready pod -l app=sidekiq -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Sidekiq timeout, continuing..."

log_info "Waiting for GitLab Shell..."
kubectl wait --for=condition=ready pod -l app=gitlab-shell -n gitlab --timeout=600s >/dev/null 2>&1 || log_warning "Shell timeout, continuing..."

log_success "Background workers operational"

log_info "Memory usage with workers:"
free -h | grep -E "Mem:|Swap:"
echo ""

sleep 20

# =============================================================================
# FASE 4: WEBSERVICE
# =============================================================================
log_header "44" "Phase 4: Webservice (Main Application)"
log_info "Deploying GitLab Webservice - most resource-intensive component"
log_warning "This phase may take 10-15 minutes"

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.enabled=true \
  --set gitlab.sidekiq.enabled=true \
  --set gitlab.gitlab-shell.enabled=true \
  --set registry.enabled=false \
  --timeout 25m \
  --wait >/dev/null 2>&1

log_success "Phase 4 completed: Webservice deployed"

log_info "Waiting for GitLab webservice (up to 15 min)..."
if kubectl -n gitlab rollout status deploy/gitlab-webservice-default --timeout=900s >/dev/null 2>&1; then
  log_success "GitLab webservice operational"
else
  log_warning "Webservice timeout"
  kubectl get pods -n gitlab -l app=webservice
fi

log_info "Memory usage with webservice:"
free -h | grep -E "Mem:|Swap:"
echo ""

sleep 20

# =============================================================================
# FASE 5: REGISTRY (Optional)
# =============================================================================
log_header "45" "Phase 5: Container Registry (Optional)"
log_warning "Registry adds ~150MB memory. Press Ctrl+C to skip"
log_info "Waiting 15 seconds..."
sleep 15

helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f /shared/confs/helm-values/gitlab-low-memory.yaml \
  --set gitlab.webservice.enabled=true \
  --set gitlab.sidekiq.enabled=true \
  --set gitlab.gitlab-shell.enabled=true \
  --set registry.enabled=true \
  --timeout 10m \
  --wait >/dev/null 2>&1 || log_warning "Registry had issues but core should work"

log_success "GitLab fully deployed"

# =============================================================================
# VERIFICATION
# =============================================================================
log_header "46" "Deployment Verification"

echo ""
log_info "Final memory status:"
free -h
echo ""

log_info "Pod status:"
kubectl get pods -n gitlab

echo ""
log_info "Resource usage:"
kubectl top nodes 2>/dev/null || log_warning "Metrics not available"
echo ""
kubectl top pods -n gitlab 2>/dev/null || log_warning "Pod metrics not available"

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