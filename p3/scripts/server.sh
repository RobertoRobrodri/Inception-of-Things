#! /bin/sh

# Install docker
echo "Installing Docker"
apk update && apk add docker
addgroup $USER docker
rc-update add docker default
service docker start

# Install kubectl
echo "Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install k3d which is k3s in docker
echo "Installing k3d"
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Install k9s because it's cool
echo "Installing k9s"
apk add k9s

# Create the cluster
k3d cluster create core -p "8888:80@loadbalancer" # expose localhost:8888 to traefik port 80

# Create the namespaces
kubectl create namespace dev
kubectl create namespace argocd

# Download ArgoCD manifest
echo "Downloading ArgoCD manifest..."
wget -O /tmp/argocd-install.yaml https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Deploy ArgoCD components gradually to avoid resource spikes
echo "Deploying ArgoCD CRDs and ConfigMaps..."
kubectl apply -n argocd -f /tmp/argocd-install.yaml --selector='!app.kubernetes.io/component'
sleep 5

echo "Deploying ArgoCD Redis..."
kubectl apply -n argocd -f /tmp/argocd-install.yaml --selector='app.kubernetes.io/component=redis'
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-redis -n argocd --timeout=300s

echo "Deploying ArgoCD Repo Server..."
kubectl apply -n argocd -f /tmp/argocd-install.yaml --selector='app.kubernetes.io/component=repo-server'
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=300s

echo "Deploying ArgoCD Application Controller..."
kubectl apply -n argocd -f /tmp/argocd-install.yaml --selector='app.kubernetes.io/component=application-controller'
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s

echo "Deploying ArgoCD Server and remaining components..."
kubectl apply -n argocd -f /tmp/argocd-install.yaml
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s

echo "ArgoCD deployed successfully!"

# Set ArgoCD dashboard pass -> holasoyadmin
sudo kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "$2a$12$gbR7bIATHJekG9kAW3pt4eoTeru957RpeotGGluQ5mS50wTm5bYU2",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'

# Apply ArgoCD ingress
kubectl apply -f /vagrant_shared/deployments/argocd-ingress.yml

# Apply ArgoCD app config
kubectl apply -f /vagrant_shared/deployments/argo.yml

# ArgoCD will automatically deploy the app from the GitHub repository
# The app includes: deployment, service, and ingress
echo "Waiting for ArgoCD to sync the application..."

# Wait for the deployment to be created by ArgoCD
echo "Waiting for deployment to be created..."
until kubectl get deployment app -n dev &> /dev/null; do
  echo "Deployment not yet created, waiting..."
  sleep 5
done

echo "Deployment created, waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods -l app=app -n dev --timeout=1800s

echo "Setup complete!"
echo "App: http://app.local:8888"
echo "ArgoCD UI: http://argocd.local:8888 (admin / holasoyadmin)"
