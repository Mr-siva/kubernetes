#!/bin/bash
set -e

echo "🔧 Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ Waiting for ArgoCD to be ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=120s

echo "🔑 Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

echo ""
echo "✅ ArgoCD installed!"
echo "Run: kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "Open: http://localhost:8080"
echo "User: admin"
echo "Password: (see above)"