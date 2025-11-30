#!/bin/sh
set -euo pipefail

# Load logging functions
. "$(dirname "$0")/logging.sh"

log_header "50" "Validating chart and deploying ArgoCD Application"

CHART_DIR="/shared/confs/charts/wil42"
APP_FILE="/shared/confs/argocd/wil42-app.yaml"

# File verification
log_info "Validating Helm Chart files"
[ -f "${CHART_DIR}/Chart.yaml" ] || { log_error "Missing ${CHART_DIR}/Chart.yaml"; exit 1; }
[ -f "${CHART_DIR}/values.yaml" ] || { log_error "Missing ${CHART_DIR}/values.yaml"; exit 1; }
[ -f "${CHART_DIR}/templates/deployment.yaml" ] || { log_error "Missing deployment.yaml"; exit 1; }
[ -f "${CHART_DIR}/templates/service.yaml" ] || { log_error "Missing service.yaml"; exit 1; }
[ -f "${CHART_DIR}/templates/ingress.yaml" ] || { log_error "Missing ingress.yaml"; exit 1; }
[ -f "${APP_FILE}" ] || { log_error "Missing ${APP_FILE} (ArgoCD Application)"; exit 1; }
log_success "All chart files are present"

# Create namespace
log_info "Creating dev namespace for application"
kubectl create namespace dev >/dev/null 2>&1 || log_info "Namespace dev already exists"

# Apply app
log_info "Deploying ArgoCD Application"
kubectl apply -f "${APP_FILE}" >/dev/null 2>&1
log_success "Application wil42 created in ArgoCD"
log_info "ArgoCD will detect changes every 3 minutes or you can do manual sync"
