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

# Wait for traefik pod to exist first
RETRY=0
MAX_RETRIES=60
until kubectl get pod -l app.kubernetes.io/name=traefik -n kube-system >/dev/null 2>&1 || [ $RETRY -eq $MAX_RETRIES ]; do
  sleep 5
  RETRY=$((RETRY + 1))
done

if [ $RETRY -eq $MAX_RETRIES ]; then
  log_error "Traefik pod not found after 2 minutes, continuing anyway"
else
  # Now wait for it to be ready
  if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=1000s >/dev/null 2>&1; then
    log_success "Traefik Ingress Controller ready"
  else
    log_error "Traefik not ready, continuing anyway"
  fi
fi
