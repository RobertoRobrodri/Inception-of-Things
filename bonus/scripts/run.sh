#!/bin/sh
set -euo pipefail

# Cargar funciones de logging
. "$(dirname "$0")/logging.sh"

sh ./scripts/00_requirements.sh
sh ./scripts/10_k3d_cluster.sh  
sh ./scripts/20_helm.sh
sh ./scripts/30_argocd.sh
sh ./scripts/40_gitlab.sh
sh ./scripts/50_app_chart.sh
sh ./scripts/60_port_forward.sh

echo
log_header "PAUSE" "Manual Configuration Required"
log_warning "Automatic setup completed. The application deployment will FAIL until you upload the repository to GitLab."
log_info "1. Access GitLab UI"
log_info "2. Create a public project and upload this repository"
log_info "3. ArgoCD will automatically detect the repository and deploy the app"
log_info "If you want to trigger a manual sync, access ArgoCD"