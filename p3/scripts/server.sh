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
k3d cluster create --agents 3 core -p "8080:8888@loadbalancer" # expose the loadbalancer port 8080 to 8888 to access the dashboard

# Create the namespaces
kubectl create namespace dev
kubectl create namespace argocd

# Apply ArgoCD deployments
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD pods to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=600s

# Set ArgoCD dashboard pass -> holasoyadmin
sudo kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "$2a$12$gbR7bIATHJekG9kAW3pt4eoTeru957RpeotGGluQ5mS50wTm5bYU2",
    "admin.passwordMtime": "'$(date +%FT%T%Z)'"
  }}'

# Apply ArgoCD app config
kubectl apply -f /vagrant_shared/deployments/argo.yml

# ArgoCD will automatically deploy the app from the GitHub repository
# The app includes: deployment, service, and ingress
echo "Waiting for ArgoCD to sync the application..."
kubectl wait --for=condition=Ready pods -l app=app -n dev --timeout=600s

echo "Setup complete! Access the app at http://app.local:8888"
