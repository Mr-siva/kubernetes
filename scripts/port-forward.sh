#!/bin/bash
# Quick port-forward helper
# Usage: bash scripts/port-forward.sh argocd|grafana|fastapi

case "$1" in
  argocd)
    echo "🔗 ArgoCD → http://localhost:8080"
    kubectl port-forward svc/argocd-server -n argocd 8080:80
    ;;
  grafana)
    echo "🔗 Grafana → http://localhost:3000"
    kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
    ;;
  fastapi)
    echo "🔗 FastAPI → http://localhost:8000"
    kubectl port-forward svc/fastapi-service 8000:80
    ;;
  *)
    echo "Usage: $0 {argocd|grafana|fastapi}"
    exit 1
    ;;
esac
