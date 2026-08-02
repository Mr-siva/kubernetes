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
| Strategy      | Behavior                          | Downtime? | Use When                    |
|---------------|-----------------------------------|-----------|-----------------------------|
| RollingUpdate | Replace pods one by one           | No        | 99% of cases (default)      |
| Recreate      | Kill ALL old → start ALL new      | Yes       | DB migrations, breaking changes |

### 2. Rollbacks

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

### 3. Liveness & Readiness Probes
*(coming next)*

### 4. Resource Limits & Requests
*(coming next)*

### 5. HorizontalPodAutoscaler (HPA)
*(coming next)*

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

# Inspect
kubectl describe deployment <name> | grep Image
kubectl describe deployment <name> | grep "text="
kubectl get replicasets                          # shows old + new RS
```

---

## Practice YAMLs

- `deployment-v1.yaml` — VERSION 1 (initial deploy, 4 replicas)
- `deployment-v2.yaml` — VERSION 2 (rolling update target)

---

## Gotchas / Mistakes I Made

- ReplicaSets don't get deleted after rollback — k8s keeps them for rollback history (that's how `undo --to-revision` works)
- `Recreate` strategy causes downtime — only use for breaking changes like DB schema migrations
- The `-w` flag on `kubectl get pods` is the best way to watch rolling updates live
- Pods showing `Error` during rollout is normal — those are old pods being terminated