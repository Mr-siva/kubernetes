#!/bin/bash
# Run from /e/kubernetes
# Usage: bash scaffold.sh

set -e

echo "🏗️  Scaffolding k8s learning repo..."

# ──────────────────────────────────────
# apps/ — your actual applications
# ──────────────────────────────────────
mkdir -p apps/fastapi-app/{src,base,overlays/{dev,staging,prod}}
mkdir -p apps/nginx-app/{src,base,overlays/{dev,staging,prod}}
mkdir -p apps/argocd-apps

# fastapi-app base manifests (shared across all envs)
cat > apps/fastapi-app/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - ingress.yaml
EOF

touch apps/fastapi-app/base/deployment.yaml
touch apps/fastapi-app/base/service.yaml
touch apps/fastapi-app/base/ingress.yaml

# dev overlay example
cat > apps/fastapi-app/overlays/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: dev
resources:
  - ../../base
patchesStrategicMerge:
  - patch-replicas.yaml
EOF

cat > apps/fastapi-app/overlays/dev/patch-replicas.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  replicas: 1
EOF

# staging overlay
cat > apps/fastapi-app/overlays/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: staging
resources:
  - ../../base
patchesStrategicMerge:
  - patch-replicas.yaml
EOF

cat > apps/fastapi-app/overlays/staging/patch-replicas.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  replicas: 2
EOF

# prod overlay
cat > apps/fastapi-app/overlays/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../base
patchesStrategicMerge:
  - patch-replicas.yaml
EOF

cat > apps/fastapi-app/overlays/prod/patch-replicas.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  replicas: 3
EOF

# ArgoCD Application manifest (points ArgoCD at your app)
cat > apps/argocd-apps/fastapi-dev.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_USERNAME/kubernetes.git
    targetRevision: main
    path: apps/fastapi-app/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# ──────────────────────────────────────
# platform/ — cluster infrastructure
# ──────────────────────────────────────
mkdir -p platform/{argocd,monitoring/{prometheus,grafana},ingress-nginx,external-secrets,rbac}

cat > platform/argocd/README.md << 'EOF'
# ArgoCD

## Install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

## Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:80

## Access
http://localhost:8080
Username: admin
EOF

cat > platform/monitoring/README.md << 'EOF'
# Monitoring Stack

## Prometheus + Grafana (via helm)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

## Port forward Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

## Grafana default creds
Username: admin
Password: prom-operator
EOF

cat > platform/ingress-nginx/README.md << 'EOF'
# Ingress NGINX Controller

## Install (KinD)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

## Verify
kubectl get pods -n ingress-nginx
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
EOF

cat > platform/external-secrets/README.md << 'EOF'
# External Secrets Operator

## Install via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

## Verify
kubectl get pods -n external-secrets
EOF

cat > platform/rbac/README.md << 'EOF'
# RBAC

Place your ClusterRole, Role, ClusterRoleBinding, RoleBinding, and ServiceAccount YAMLs here.
EOF

# ──────────────────────────────────────
# helm-charts/ — custom charts
# ──────────────────────────────────────
mkdir -p helm-charts/fastapi-chart/templates

cat > helm-charts/fastapi-chart/Chart.yaml << 'EOF'
apiVersion: v2
name: fastapi-chart
description: Helm chart for FastAPI application
type: application
version: 0.1.0
appVersion: "1.0.0"
EOF

cat > helm-charts/fastapi-chart/values.yaml << 'EOF'
replicaCount: 2

image:
  repository: fastapi-app
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  host: fastapi.local
  path: /api

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
EOF

touch helm-charts/fastapi-chart/templates/deployment.yaml
touch helm-charts/fastapi-chart/templates/service.yaml
touch helm-charts/fastapi-chart/templates/ingress.yaml
touch helm-charts/fastapi-chart/templates/_helpers.tpl

# ──────────────────────────────────────
# scripts/ — automation
# ──────────────────────────────────────
mkdir -p scripts

cat > scripts/setup-cluster.sh << 'SCRIPT'
#!/bin/bash
set -e
CLUSTER_NAME=${1:-k8s-lab}

echo "🚀 Creating KinD cluster: $CLUSTER_NAME"
kind create cluster --name $CLUSTER_NAME --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF

echo "📦 Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

echo "🔑 Installing external-secrets operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --wait

echo "✅ Cluster ready: $CLUSTER_NAME"
kubectl get nodes
SCRIPT

cat > scripts/teardown-cluster.sh << 'SCRIPT'
#!/bin/bash
CLUSTER_NAME=${1:-k8s-lab}
echo "🗑️  Deleting KinD cluster: $CLUSTER_NAME"
kind delete cluster --name $CLUSTER_NAME
echo "✅ Done"
SCRIPT

cat > scripts/port-forward.sh << 'SCRIPT'
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
SCRIPT

chmod +x scripts/*.sh

# ──────────────────────────────────────
# exercises/ — one folder per topic
# ──────────────────────────────────────
TOPICS=(
  "01-pods-deployments"
  "02-namespaces"
  "03-configmaps-secrets"
  "04-external-secrets"
  "05-services-ingress"
  "06-deployments-deep-dive"
  "07-persistent-volumes"
  "08-rbac-security"
  "09-helm"
  "10-statefulsets"
  "11-monitoring"
  "12-cicd-argocd"
)

for topic in "${TOPICS[@]}"; do
  mkdir -p "exercises/$topic"
  cat > "exercises/$topic/README.md" << EOF
# ${topic#*-}

## What I learned

## Key commands

## Practice YAMLs
- See .yaml files in this folder

## Gotchas / mistakes I made
EOF
done

# ──────────────────────────────────────
# .gitignore
# ──────────────────────────────────────
cat > .gitignore << 'EOF'
# Secrets - NEVER commit these
*-secret.yaml
*secret*.yaml
.env
*.pem
*.key

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Temp
*.tmp
*.bak
EOF

echo ""
echo "✅ Scaffold complete! Structure:"
echo ""
find . -type f -not -path './.git/*' | head -60 | sort
echo ""
echo "📁 Total files: $(find . -type f -not -path './.git/*' | wc -l)"
echo "📂 Total folders: $(find . -type d -not -path './.git/*' | wc -l)"
echo ""
echo "Next steps:"
echo "  1. Move your existing YAMLs into the right exercise folders"
echo "  2. Update apps/argocd-apps/fastapi-dev.yaml with your GitHub URL"
echo "  3. Start with: cd exercises/06-deployments-deep-dive"