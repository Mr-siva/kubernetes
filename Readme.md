# Kubernetes Command Reference

Personal reference doc — commands for everything covered so far.
Cluster used for practice: **KinD**

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

# ARGO CD

```bash

kubectl get svc -n argocd

# port forarding
kubectl port-forward svc/argocd-server -n argocd 8080:80

# to her pw
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

user - admni
pw   -  



```


---

## 1. Pods & Deployments

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

**Rule of thumb:** never run standalone Pods in prod — always go through a Deployment.

---

## 2. Namespaces

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

**Rule of thumb:** one namespace per team/environment (dev/staging/prod).

---

## 3. ConfigMaps

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

**Rule of thumb:** volume-mounted ConfigMaps auto-update without a pod restart; env-var ConfigMaps are static and need a restart.

---

## 4. Secrets

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

**Rule of thumb:** Secrets are base64-encoded, NOT encrypted. Always volume-mount in production. Never hardcode secrets or commit them to Git.

---

## 5. External Secrets Operator (AWS Secrets Manager → k8s)

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

**Rule of thumb:** `ExternalSecret.target.name` MUST match the `secretName` referenced in the Pod's volume.

---

## 6. Services & Networking

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

**Service types:**
| Type | Scope |
|---|---|
| ClusterIP | internal only (pod-to-pod) |
| NodePort | external via node IP + port |
| LoadBalancer | external via cloud LB (prod) |

**Rule of thumb:** Service `selector` must match Pod `labels` exactly — that's how traffic gets routed. A Service load-balances automatically across all matched pods.

---

## 7. Ingress

```bash
kubectl get ingress
kubectl get ing
kubectl describe ingress <name>
kubectl delete ingress <name>

# Ingress controller (e.g. nginx) lives in its own namespace
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx <controller-pod-name>
kubectl describe pod <controller-pod-name> -n ingress-nginx
```

**Key YAML fields:** `ingressClassName`, `host`, `path`, `pathType` (Exact/Prefix), `backend.service`, `annotations` (rewrite rules, timeouts, etc.)

**Rule of thumb:** one domain, many services, all routed by a single Ingress.

---

## 8. General Debugging & Cluster-Wide Commands

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

**Debugging order that usually works:**
1. `kubectl get pods` → is it even running?
2. `kubectl describe pod <name>` → check Events at the bottom
3. `kubectl logs <name>` → app-level errors
4. `kubectl get events --sort-by='.lastTimestamp'` → cluster-wide view

---

## Architecture Built So Far

```
AWS Secrets Manager
        │  ExternalSecret syncs
        ▼
k8s Secret (auto-created)
        │  Volume mount
        ▼
FastAPI Pod (/etc/secrets/)
        │  ClusterIP Service
        ▼
fastapi-service:80
        │  Ingress routes by path
        ▼
fastapi.local/api/*  → fastapi-service
fastapi.local/web/*  → nginx-service
```

---

## Roadmap — What's Next

- [ ] **Deployments Deep Dive** — rolling updates, rollbacks, liveness/readiness probes, resource limits & requests, HPA
- [ ] Persistent Volumes & Storage
- [ ] RBAC & Security
- [ ] Helm Charts
- [ ] StatefulSets
- [ ] Monitoring (Prometheus + Grafana)
- [ ] CI/CD (ArgoCD)