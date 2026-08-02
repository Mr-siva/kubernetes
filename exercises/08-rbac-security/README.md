# RBAC & Security

## What I Learned

### The Problem
Without RBAC, everyone has full admin access. A developer could accidentally delete production, an intern could read all secrets, a CI/CD pipeline has unlimited power.

### RBAC = Role-Based Access Control
**Who** can do **what**, **where**.

```
RBAC is DENY-BY-DEFAULT:
  Listed in rules?   → allowed
  NOT listed?        → denied
  You never write "deny" rules — you only write "allow" rules
```

### 4 Objects

```
ServiceAccount     → WHO (identity for pods/apps)
Role               → WHAT + WHERE (permissions in ONE namespace)
ClusterRole        → WHAT + WHERE (permissions across ALL namespaces)
RoleBinding        → connects ServiceAccount → Role
ClusterRoleBinding → connects ServiceAccount → ClusterRole
```

### How the YAMLs Connect

```
serviceaccount.yaml          role.yaml                  rolebinding.yaml
┌──────────────────┐        ┌──────────────────┐       ┌──────────────────────┐
│ ServiceAccount   │        │ Role             │       │ RoleBinding          │
│ name: dev-user   │◀───────│ name: pod-reader │◀──────│ name: dev-user-      │
│                  │  WHO   │                  │ WHAT  │       pod-reader     │
│ (identity)       │        │ rules:           │       │                      │
│                  │        │  pods: get,list  │       │ subjects:            │
└──────────────────┘        │  (read only)     │       │   name: dev-user     │
                            └──────────────────┘       │ roleRef:             │
                                                       │   name: pod-reader   │
                                                       └──────────────────────┘
```

### Role vs ClusterRole

```
Role + RoleBinding:
  get pods default     → yes
  get pods kube-system → no     ← scoped to ONE namespace
  get pods argocd      → no

ClusterRole + ClusterRoleBinding:
  get pods default     → yes
  get pods kube-system → yes    ← ALL namespaces
  get pods argocd      → yes
```

### Role YAML Explained

```yaml
rules:
- apiGroups: [""]              # "" = core API (pods, services, secrets, configmaps)
  resources: ["pods"]          # which resource type
  verbs: ["get", "list", "watch"]   # what actions are allowed
```

**apiGroups reference:**
```
""           → core: pods, services, secrets, configmaps, namespaces, nodes
"apps"       → deployments, replicasets, statefulsets, daemonsets
"networking.k8s.io" → ingress, networkpolicies
"rbac.authorization.k8s.io" → roles, rolebindings
```

**Common verbs:**
```
get      → read one resource
list     → read all resources
watch    → stream changes
create   → make new resource
update   → modify existing
patch    → partial update
delete   → remove resource
```

### Prod RBAC Patterns

```
Developers (read-only):
  pods, services, configmaps → get, list, watch

DevOps/SRE (full control):
  deployments, services, configmaps → get, list, create, update, delete

CI/CD pipeline (deploy only):
  deployments → get, list, create, update, patch
  services    → get, list, create, update
  pods        → get, list, watch
  secrets     → (not listed = no access)

Admin:
  cluster-admin built-in role → everything everywhere
```

### CI/CD Deployer Test Results

```
create deployments → yes ✅  (needs to deploy)
update deployments → yes ✅  (needs to update)
create services    → yes ✅  (needs to expose apps)
get pods           → yes ✅  (needs to check status)
get secrets        → no  🚫  (not listed = denied)
delete deployments → no  🚫  (not listed = denied)
```

### Multiple Resources in One File

Use `---` separator:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cicd-deployer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer
rules:
  ...
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
  ...
```

---

## Key Commands

```bash
# ServiceAccount
kubectl get serviceaccounts
kubectl get sa
kubectl describe sa <name>

# Roles
kubectl get roles
kubectl get clusterroles
kubectl describe role <name>
kubectl describe clusterrole <name>

# Bindings
kubectl get rolebindings
kubectl get clusterrolebindings
kubectl describe rolebinding <name>

# Test permissions (impersonate a service account)
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<namespace>:<sa-name>
kubectl auth can-i get pods --as=system:serviceaccount:default:dev-user
kubectl auth can-i delete pods --as=system:serviceaccount:default:dev-user -n kube-system

# Check what a user CAN do (all permissions)
kubectl auth can-i --list --as=system:serviceaccount:default:dev-user
```

---

## Practice YAMLs

- `serviceaccount.yaml` — dev-user ServiceAccount
- `role.yaml` — pod-reader Role (get/list/watch pods in default ns)
- `rolebinding.yaml` — binds dev-user → pod-reader
- `clusterrole.yaml` — cluster-pod-reader (get/list/watch pods in ALL ns)
- `clusterrolebinding.yaml` — binds dev-user → cluster-pod-reader
- `cicd-role.yaml` — CI/CD deployer (SA + Role + RoleBinding in one file)

---

## Gotchas / Mistakes I Made

- **RBAC is deny-by-default** — if you don't list a resource/verb, it's blocked. No need to explicitly deny
- Empty `verbs: []` is invalid — k8s requires at least one verb per rule. Just don't include the resource at all
- `Role` is namespace-scoped — dev-user could get pods in default but NOT in kube-system
- `ClusterRole` works across ALL namespaces — same permissions everywhere
- `kubectl auth can-i` is the best debugging tool — test before deploying
- The `--as=` flag uses format: `system:serviceaccount:<namespace>:<name>`
- `---` separator lets you put multiple resources in one YAML file