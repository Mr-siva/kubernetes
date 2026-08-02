# Deployments Deep Dive

## What I Learned

### 1. Rolling Updates
- k8s replaces pods **gradually**, not all at once → zero downtime
- Controlled by `strategy` in Deployment spec

```yaml
strategy:
  type: RollingUpdate          # other option: Recreate (kill all, then create all)
  rollingUpdate:
    maxSurge: 1                # max EXTRA pods during update (replicas + 1)
    maxUnavailable: 1          # max pods DOWN during update (replicas - 1)
```

**How it works (4 replicas, maxSurge: 1, maxUnavailable: 1):**
```
Time 0:  v1 v1 v1 v1          ← 4 pods running v1
Time 1:  v1 v1 v1 v1 v2       ← 1 new v2 created (maxSurge allows 5 total)
Time 2:  v1 v1 v1 -- v2       ← 1 old v1 killed (maxUnavailable allows 3 minimum)
Time 3:  v1 v1 v1 v2 v2       ← another v2 created
Time 4:  v1 v1 -- v2 v2       ← another v1 killed
...
Final:   v2 v2 v2 v2          ← all v2, ZERO downtime
```

**Strategy comparison:**

| Strategy      | Behavior                     | Downtime? | Use When                        |
|---------------|------------------------------|-----------|---------------------------------|
| RollingUpdate | Replace pods one by one      | No        | 99% of cases (default)          |
| Recreate      | Kill ALL old → start ALL new | Yes       | DB migrations, breaking changes |

---

### 2. Rollbacks

k8s keeps old ReplicaSets around so you can rollback instantly.

```bash
# See all revisions
kubectl rollout history deployment webapp

# See specific revision details
kubectl rollout history deployment webapp --revision=2

# Rollback to previous version
kubectl rollout undo deployment webapp

# Rollback to specific revision
kubectl rollout undo deployment webapp --to-revision=1

# Watch rollback progress
kubectl rollout status deployment webapp
```

---

### 3. Liveness & Readiness Probes

```
Liveness Probe  → "Is this pod ALIVE?"
                   Fail → k8s KILLS and RESTARTS it

Readiness Probe → "Is this pod READY for traffic?"
                   Fail → k8s REMOVES it from Service (no traffic sent)
```

**Analogy:**
```
Liveness  = is the restaurant open? (lights on, door unlocked)
Readiness = is the kitchen ready to take orders?

Open but kitchen not ready → don't send customers yet
```

**Probe config:**
```yaml
livenessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 5      # wait 5s after startup before first check
  periodSeconds: 10           # check every 10s
  failureThreshold: 3         # 3 failures in a row → KILL and restart

readinessProbe:
  httpGet:
    path: /
    port: 8080
  initialDelaySeconds: 3      # wait 3s before first check
  periodSeconds: 5            # check every 5s
  failureThreshold: 2         # 2 failures → remove from Service
```

**3 probe methods:**
```yaml
httpGet:                        # HTTP request — most common for web apps
  path: /health
  port: 8080

tcpSocket:                      # TCP connection — good for databases
  port: 3306

exec:                           # Run a command inside container
  command: ["cat", "/tmp/healthy"]
```

**Describe output decoded:**
```
Liveness:  http-get http://:8080/ delay=5s timeout=1s period=10s #success=1 #failure=3
           │                      │        │          │           │          │
           │                      │        │          │           │          └─ 3 fails → KILL
           │                      │        │          │           └─ 1 pass → alive
           │                      │        │          └─ check every 10s
           │                      │        └─ respond within 1s
           │                      └─ wait 5s after start
           └─ GET request to port 8080
```

---

### 4. Resource Limits & Requests

```
requests = "minimum guaranteed" → k8s uses for SCHEDULING (which node has space?)
limits   = "maximum allowed"   → k8s uses for ENFORCEMENT (kill/throttle if exceeded)
```

```yaml
resources:
  requests:
    cpu: 100m            # 100 millicores = 0.1 CPU (10% of 1 core)
    memory: 64Mi         # 64 megabytes minimum
  limits:
    cpu: 200m            # max 0.2 CPU
    memory: 128Mi        # max 128MB
```

**What happens when limits are hit:**
```
CPU exceeded?    → pod gets THROTTLED (slowed down, NOT killed)
Memory exceeded? → pod gets OOMKilled (killed immediately!)
```

**Common values reference:**
```
Small app (echo server, simple API):
  requests: cpu: 50m,  memory: 64Mi
  limits:   cpu: 200m, memory: 128Mi

Medium app (FastAPI with DB calls):
  requests: cpu: 100m, memory: 128Mi
  limits:   cpu: 500m, memory: 256Mi

Heavy app (ML model, data processing):
  requests: cpu: 500m, memory: 512Mi
  limits:   cpu: 2000m, memory: 2Gi
```

**Requires metrics-server for `kubectl top`:**
```bash
# Install metrics-server (KinD needs --kubelet-insecure-tls patch)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'
```

---

### 5. HorizontalPodAutoscaler (HPA)

Auto-scales replicas based on CPU/memory usage.

```
Low traffic  → 2 pods (minReplicas)
High traffic → 8 pods (maxReplicas)
Traffic dies → back to 2 pods (scale-down, ~5 min delay)
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp-resources         # which deployment to scale
  minReplicas: 2                   # never below 2
  maxReplicas: 8                   # never above 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50     # if avg CPU > 50% of request → scale UP
```

**HPA math:**
```
pods request 100m CPU each
target = 50% of 100m = 50m

avg CPU > 50m → scale UP
avg CPU < 50m → scale DOWN (to minReplicas)

Formula: desiredReplicas = ceil(currentReplicas × (currentUtilization / targetUtilization))
Example: 2 pods at 108% → ceil(2 × 108/50) = ceil(4.32) = 5 pods
```

**What I saw during load test:**
```
cpu: 1%/50%    → 2 pods (idle)
cpu: 108%/50%  → HPA scales to 4
cpu: 158%/50%  → HPA scales to 7
cpu: 76%/50%   → holding, load spreading
cpu: 52%/50%   → stabilizing near target
(after load removed → scales back to 2 in ~5 min)
```

**HPA depends on metrics-server being installed.**

---

## Key Commands

```bash
# Rolling update
kubectl apply -f deployment-v2.yaml
kubectl rollout status deployment <name>
kubectl get pods -l app=<label> -w              # watch live

# Rollback
kubectl rollout history deployment <name>
kubectl rollout undo deployment <name>
kubectl rollout undo deployment <name> --to-revision=N

# Probes
kubectl describe pod <name> | grep -A 5 "Liveness\|Readiness"

# Resources
kubectl describe pod <name> | grep -A 6 "Limits\|Requests"
kubectl top nodes
kubectl top pods

# HPA
kubectl get hpa
kubectl get hpa -w                               # watch scaling live
kubectl describe hpa <name>

# Load testing
export MSYS_NO_PATHCONV=1                        # Git Bash / MINGW fix!
kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://<service-name> > /dev/null 2>&1; done"
kubectl delete pod load-generator

# Inspect
kubectl describe deployment <name> | grep Image
kubectl get replicasets                          # shows old + new RS
```

---

## Practice YAMLs

- `deployment-v1.yaml` — VERSION 1 (initial deploy, 4 replicas, rolling update strategy)
- `deployment-v2.yaml` — VERSION 2 (rolling update target)
- `deployment-probes.yaml` — liveness + readiness probes
- `deployment-resources.yaml` — resource requests + limits + probes
- `hpa.yaml` — HorizontalPodAutoscaler

---

## Gotchas / Mistakes I Made

- ReplicaSets don't get deleted after rollback — k8s keeps them for history
- `Recreate` strategy causes downtime — only use for breaking changes
- Pods showing `Error` during rollout is normal — old pods terminating
- `kubectl top` needs metrics-server installed — won't work without it
- **Git Bash / MINGW converts `/bin/sh` to Windows path** — fix with `export MSYS_NO_PATHCONV=1`
- HPA scale-down is slow (~5 min) — by design, prevents flapping
- Memory limit exceeded = OOMKilled (instant kill), CPU limit = throttle (just slower)
- HPA needs resource `requests` set on pods — without requests, it can't calculate utilization %