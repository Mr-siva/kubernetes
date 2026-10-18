# Kubernetes Learning — Complete Reference

Personal reference doc — commands, concepts, examples, and folder structure.
Cluster: **KinD** | App: **FastAPI + Nginx** | Secrets: **AWS Secrets Manager**

---

## Repo Folder Structure

```
e/kubernetes/
├── Readme.md                          ← YOU ARE HERE
├── Scaffold.sh
│
├── apps/                              ← Your actual applications
│   ├── fastapi-app/
│   │   ├── src/                       ← App source code + Dockerfile
│   │   ├── base/                      ← Shared k8s manifests (Kustomize)
│   │   │   ├── kustomization.yaml
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   └── ingress.yaml
│   │   └── overlays/                  ← Per-environment overrides
│   │       ├── dev/                   ← 1 replica
│   │       ├── staging/               ← 2 replicas
│   │       └── prod/                  ← 3 replicas
│   ├── nginx-app/                     ← Same structure
│   └── argocd-apps/                   ← ArgoCD Application YAMLs
│       └── fastapi-dev.yaml           ← Points ArgoCD at apps/fastapi-app/overlays/dev
│
├── platform/                          ← Cluster infrastructure (installed once)
│   ├── argocd/                        ← ArgoCD install + config
│   ├── monitoring/                    ← Prometheus + Grafana
│   │   ├── prometheus/
│   │   └── grafana/
│   ├── ingress-nginx/                 ← Ingress controller setup
│   ├── external-secrets/              ← ESO install + config
│   └── rbac/                          ← Roles, bindings, service accounts
│
├── helm-charts/                       ← Custom Helm charts you build
│   └── fastapi-chart/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│
├── scripts/                           ← Automation
│   ├── setup-cluster.sh               ← Creates KinD + installs platform tools
│   ├── teardown-cluster.sh            ← Destroys cluster
│   └── port-forward.sh                ← Quick port-forward helper
│
└── exercises/                         ← One folder per learning topic
    ├── 01-pods-deployments/
    ├── 02-namespaces/
    ├── 03-configmaps-secrets/
    ├── 04-external-secrets/
    ├── 05-services-ingress/
    ├── 06-deployments-deep-dive/
    ├── 07-scheduling-taints-tolerations/
    ├── 08-persistent-volumes/
    ├── 09-rbac-security/
    ├── 10-helm/
    ├── 11-statefulsets/
    ├── 12-monitoring/
    └── 13-cicd-argocd/
```

**Why this structure?**
- `apps/` uses **Kustomize overlays** — same base YAML, different config per env (exactly how Netflix, Airbnb do it)
- `platform/` separates infra from app code — installed once, shared by all apps
- `exercises/` is your sandbox — practice YAMLs + notes per topic
- `apps/argocd-apps/` — ArgoCD watches Git and auto-deploys on `git push`

---

## 0. Cluster & Context Management

```bash
# KinD cluster lifecycle
kind create cluster --name <cluster-name>
kind get clusters
kind delete cluster --name <cluster-name>
kind load docker-image <image-name> --name <cluster-name>   # push local image into KinD

# Context / config
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <context-name>
kubectl config view
kubectl cluster-info
kubectl get nodes
kubectl describe node <node-name>
```

---

## 1. Pods & Deployments ✅

**Concepts:**
- Pod = smallest unit, wraps a container
- Deployment = manages pods (replicas, updates, restarts)
- ReplicaSet = ensures N pods always running
- Never run standalone pods in prod — always use Deployments

```bash
kubectl apply -f deployment.yaml
kubectl get pods
kubectl get pods -o wide
kubectl get deployments
kubectl get deploy

kubectl describe pod <pod-name>
kubectl describe deployment <deployment-name>

kubectl delete pod <pod-name>              # deployment recreates it automatically
kubectl delete deployment <deployment-name>
kubectl delete -f deployment.yaml

kubectl logs <pod-name>
kubectl logs -f <pod-name>                 # follow/stream logs
kubectl logs <pod-name> -c <container-name> # multi-container pod

kubectl exec -it <pod-name> -- sh
kubectl exec -it <pod-name> -- bash

kubectl scale deployment <name> --replicas=3
kubectl rollout restart deployment <name>
kubectl rollout status deployment <name>
```

---

## 2. Namespaces ✅

**Concepts:**
- Logical separation inside a cluster (like folders for k8s objects)
- One namespace per team/environment (dev/staging/prod)

```bash
kubectl create namespace <name>
kubectl get namespaces
kubectl get ns
kubectl delete namespace <name>

kubectl config set-context --current --namespace=<name>
kubectl config view --minify | grep namespace:

kubectl get pods -n <namespace>
kubectl get pods --all-namespaces
kubectl get pods -A
```

---

## 3. ConfigMaps ✅

**Concepts:**
- Store non-sensitive config (URLs, ports, env names)
- Two ways to use:
  - Env vars → static, needs pod restart
  - Volume mount → dynamic, auto-updates (PREFERRED)

```bash
kubectl create configmap <name> --from-literal=KEY=value
kubectl create configmap <name> --from-file=path/to/file
kubectl create configmap <name> --from-env-file=path/to/.env

kubectl get configmap
kubectl get cm
kubectl describe configmap <name>
kubectl get configmap <name> -o yaml

kubectl edit configmap <name>
kubectl delete configmap <name>
```

---

## 4. Secrets ✅

**Concepts:**
- Store sensitive config (passwords, API keys, tokens)
- Base64 encoded (NOT encrypted!)
- Same two ways: env vars or volume mount
- Production rule: ALWAYS use volume mount
- NEVER hardcode secrets in code or commit to Git

```bash
kubectl create secret generic <name> --from-literal=KEY=value
kubectl create secret generic <name> --from-file=path/to/file

kubectl get secret
kubectl get secrets
kubectl describe secret <name>
kubectl get secret <name> -o yaml

# Decode a secret value
kubectl get secret <name> -o jsonpath='{.data.<key>}' | base64 --decode

kubectl delete secret <name>
```

---

## 5. External Secrets Operator (AWS Secrets Manager → k8s) ✅

**Concepts:**
```
AWS Secrets Manager          KinD Cluster
┌──────────────┐            ┌─────────────────────┐
│ my/app/keys  │            │ ClusterSecretStore  │
│ API_KEY      │◀───────────│ (AWS auth config)   │
│ DB_PASSWORD  │            │ ExternalSecret      │
│ user_name_is │            │ (fetch rules)       │
└──────────────┘            │ ↓                   │
                            │ k8s Secret          │
                            │ (auto-created)      │
                            │ ↓                   │
                            │ Pod /etc/secrets/   │
                            └─────────────────────┘
```

3 YAMLs you write:

| YAML               | Job                                |
|---------------------|------------------------------------|
| ClusterSecretStore  | HOW to connect to AWS              |
| ExternalSecret      | WHAT to fetch + WHERE to store     |
| Pod/Deployment      | HOW to use (volume mount)          |

**Critical:** `ExternalSecret.target.name` MUST match `Pod.volumes.secret.secretName`

**Full Flow — How All 3 YAMLs Connect:**
```
secret-store.yaml              ExternalSecret.yaml           pod.yaml
┌─────────────────┐           ┌──────────────────────┐      ┌─────────────────────────┐
│ SecretStore     │           │ ExternalSecret        │      │ volumes:                │
│ name:           │◀──────────│ secretStoreRef:       │      │  - name: secret-vol     │
│  aws-secret-    │  refers   │   name: aws-secret-   │      │    secret:              │
│  store          │  to       │   store               │      │     secretName:         │
│                 │           │                       │      │      my-app-secrets ────┼──┐
│ AWS credentials │           │ target:               │      │                         │  │
│ region          │           │   name: my-app-secrets│      │ volumeMounts:           │  │
└─────────────────┘           │                       │      │  - name: secret-vol     │  │
        │                     │ dataFrom:             │      │    mountPath:           │  │
        │                     │   key: my/app/keys    │      │     /etc/secrets        │  │
        ▼                     └──────────────────────┘      └─────────────────────────┘  │
AWS Secrets Manager                     │                               │                │
my/app/keys                             │ creates                       │ mounts         │
{"API_KEY": "abc",                      ▼                               │                │
 "DB_PASS": "xyz"}          k8s Secret "my-app-secrets" ───────────────┘                │
                            API_KEY = "abc"          ◀───────────────────────────────────┘
                            DB_PASS = "xyz"          same name referenced
                                        │
                                        │ volume loads secret
                                        ▼
                                 Volume "secret-vol"
                                 (truck carrying data)
                                        │
                                        │ mounted at
                                        ▼
                            Container /etc/secrets/
                            ├── API_KEY  = "abc"
                            └── DB_PASS  = "xyz"
                                        │
                                        │ app reads files
                                        ▼
                            Python FastAPI
                            open("/etc/secrets/API_KEY")
                            → "abc" ✅
```

```bash
kubectl get clustersecretstore
kubectl describe clustersecretstore <name>

kubectl get externalsecret
kubectl get es
kubectl describe externalsecret <name>

kubectl get secretstore -n <namespace>

# Check the operator itself
kubectl get pods -n external-secrets
kubectl logs -n external-secrets deployment/external-secrets
```

---

## 6. Services & Networking ✅

**Concepts:**
- Problem: Pods have unstable IPs
- Solution: Service gives stable endpoint
- Service `selector` must match Pod `labels` exactly
- Service load balances automatically across all matched pods

| Type         | Scope                          |
|--------------|--------------------------------|
| ClusterIP    | internal only (pod-to-pod)     |
| NodePort     | external via node IP + port    |
| LoadBalancer | external via cloud LB (prod)   |

**How Service finds Pods:**
```yaml
# Service selector
selector:
  app: fastapi-app    # finds ALL pods with this label

# Pod label (must match!)
labels:
  app: fastapi-app
```

```bash
kubectl get svc
kubectl get services
kubectl describe svc <name>

kubectl expose deployment <name> --port=80 --target-port=8080 --type=ClusterIP

kubectl port-forward service/<name> 8080:80
kubectl port-forward pod/<pod-name> 8080:80

kubectl get endpoints
kubectl describe endpoints <name>
```

---

## 7. Ingress ✅

**Concepts:**
- Problem: One service = one port (messy with 10 services!)
- Solution: Ingress routes by URL path — one domain, many services
- Two parts:
  - Ingress Controller = actual nginx pod (installed once)
  - Ingress Rules = your YAML (routing rules per app)

```
fastapi.local
    ├── /api/* → fastapi-service ✅
    └── /web/* → nginx-service   ✅
```

**Ingress YAML explained:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /    # strips prefix before sending to pod
spec:
  ingressClassName: nginx      # which controller handles this
  rules:
  - host: fastapi.local        # which domain to match
    http:
      paths:
      - path: /                # which URL path to match
        pathType: Prefix       # Prefix = /anything matches. Exact = only exact match
        backend:
          service:
            name: fastapi-service   # where to send matched request
            port:
              number: 80
```

**Rewrite target explained:**
```
Request comes in:   fastapi.local/api/health
Strip the prefix:   /api
Send to pod as:     /health

Without rewrite:    pod receives /api/health  ❌ (route might not exist)
With rewrite:       pod receives /health      ✅
```

**Multi-path routing (prod pattern):**
```yaml
rules:
- host: api.mycompany.com
  http:
    paths:
    - path: /users
      pathType: Prefix
      backend:
        service:
          name: user-service
          port:
            number: 80
    - path: /orders
      pathType: Prefix
      backend:
        service:
          name: order-service
          port:
            number: 80
    - path: /payments
      pathType: Prefix
      backend:
        service:
          name: payment-service
          port:
            number: 80
```

| Field            | Purpose                              |
|------------------|--------------------------------------|
| ingressClassName | Which controller handles this        |
| host             | Which domain to match                |
| path             | Which URL path to match              |
| pathType         | Exact or Prefix matching             |
| backend.service  | Where to send matched request        |
| annotations      | Extra nginx config (rewrite, etc)    |

**Testing without sudo (no /etc/hosts needed):**
```bash
curl -H "Host: fastapi.local" http://localhost/health
curl -H "Host: fastapi.local" http://localhost/user
```

```bash
# Install ingress controller (KinD)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

kubectl get pods -n ingress-nginx
kubectl get ingress
kubectl get ing
kubectl describe ingress <name>
kubectl delete ingress <name>

# Ingress controller logs
kubectl logs -n ingress-nginx <controller-pod-name>
kubectl describe pod <controller-pod-name> -n ingress-nginx
```

---

## ArgoCD

```bash
# Install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward (HTTP — insecure mode)
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Access
# http://localhost:8080
# Username: admin

# Check services & pods
kubectl get svc -n argocd
kubectl get pods -n argocd
kubectl describe svc argocd-server -n argocd
```

**Quick port-forward helper:** `bash scripts/port-forward.sh argocd`

---

## General Debugging & Cluster-Wide Commands

```bash
kubectl get all
kubectl get all -n <namespace>

kubectl get events
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n <namespace>

kubectl top pods
kubectl top nodes

kubectl api-resources
kubectl explain <resource>
kubectl explain <resource>.<field>       # e.g. kubectl explain pod.spec.containers

kubectl describe pod <name>              # check the Events section first when debugging
```

**Debugging order:**
1. `kubectl get pods` → is it even running?
2. `kubectl describe pod <name>` → check Events at the bottom
3. `kubectl logs <name>` → app-level errors
4. `kubectl get events --sort-by='.lastTimestamp'` → cluster-wide view

---

## Full Prod Architecture (What I Built)

```
AWS Secrets Manager
user_name_is = "siva"
API_KEY = "myapikey456"
        │
        │ ExternalSecret syncs
        ▼
k8s Secret "my-app-secrets" (auto-created)
        │
        │ Volume mount
        ▼
FastAPI Pod (/etc/secrets/)
        │
        │ ClusterIP Service
        ▼
fastapi-service:80
        │
        │ Ingress routes by path
        ▼
fastapi.local/api/* → fastapi-service
fastapi.local/web/* → nginx-service
        │
        │ (prod: Route53 → ALB → Ingress)
        ▼
Browser/Client
{"username":"siva","message":"Hello, siva!"}
```

---

## Roadmap

- [x] Pods & Deployments
- [x] Namespaces
- [x] ConfigMaps
- [x] Secrets
- [x] External Secrets Operator (AWS)
- [x] Services & Networking
- [x] Ingress
- [ ] **Deployments Deep Dive** — rolling updates, rollbacks, probes, resource limits, HPA ← NEXT
- [ ] Persistent Volumes & Storage
- [ ] RBAC & Security
- [ ] Helm Charts
- [ ] StatefulSets
- [ ] Monitoring (Prometheus + Grafana)
- [ ] CI/CD (ArgoCD)