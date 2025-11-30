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
log_info "Waiting for Traefik to be ready..."
sleep 20
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=300s >/dev/null 2>&1; then
  log_success "Traefik Ingress Controller ready"
else
  log_error "Traefik not available, continuing anyway"
fi
