#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "10" "Creating k3d cluster"

CLUSTER="iot-cluster"

# Create k3d cluster with Traefik
log_info "Creating ${CLUSTER} cluster with Traefik Ingress Controller"
if k3d cluster list | grep -q "^${CLUSTER}\b"; then
  log_info "Cluster ${CLUSTER} already exists, skipping creation"
else
  k3d cluster create "${CLUSTER}" \
    --k3s-arg "--disable=servicelb@server:0" >/dev/null 2>&1
  log_success "k3d cluster created successfully"
fi

# Wait for API to respond
log_info "Verifying cluster connection"
kubectl version --client >/dev/null 2>&1
log_success "kubectl client connected to cluster"

# Wait for traefik to be available
log_info "Waiting for Traefik installation job to complete..."

# First wait for the helm-install-traefik job to complete
if kubectl wait --for=condition=complete job/helm-install-traefik -n kube-system --timeout=300s >/dev/null 2>&1; then
  log_success "Traefik Helm installation completed"
else
  log_error "Traefik installation job did not complete, continuing anyway"
fi

# Now wait for traefik deployment to be ready
log_info "Waiting for Traefik deployment to be ready..."
if kubectl wait --for=condition=available deployment/traefik -n kube-system --timeout=300s >/dev/null 2>&1; then
  log_success "Traefik Ingress Controller ready"
else
  log_error "Traefik deployment not ready, continuing anyway"
fi
