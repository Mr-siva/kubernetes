# scheduling

CKA "Scheduling" domain, done on a single-node KinD cluster (`my-cluster`). Topics 4/5/10/12 below only
show correct YAML/syntax here - they need 2+ nodes to demonstrate actual node selection, which this
cluster doesn't have (chose to stay single-node to keep ArgoCD/dev state intact for the Sunday session).

## Topics
1. Manual Scheduling (`nodeName`)
2. Labels & Selectors / `nodeSelector` - done
3. Taints & Tolerations - done
4. Node Affinity - done (required + preferred rules; single-node so can't prove node *selection*, only that matching works)
5. Pod Affinity / Anti-Affinity (syntax only)
6. Taints+Tolerations vs Node Affinity (combined use) - done (see notes below)
7. Resource Requests/Limits effect on scheduling - see exercises/06-deployments-deep-dive
8. DaemonSets
9. Static Pods
10. Multiple Schedulers (syntax only)
11. Priority Classes & Preemption
12. Pod Topology Spread Constraints (syntax only)
13. Cordon / Drain / Uncordon

(Hands-on for 2-4 and 6 was done on KodeKloud's CKA labs; YAMLs below were then written and verified for real against `my-cluster` to keep this repo self-contained.)

## What I learned

### Taints & Tolerations
- Taint = on the **node**, repels pods. Toleration = on the **pod**, permits (doesn't force) scheduling there.
- Tolerating a taint never *guarantees* placement on that node - it only removes the block. Use node affinity if you actually want to steer the pod there.
- 3 effects:
  - `NoSchedule` - blocks new pods only. Pods already running before the taint was added are left alone.
  - `PreferNoSchedule` - soft `NoSchedule`. Scheduler tries to avoid the node but will still use it if there's no better option.
  - `NoExecute` - strictest. Blocks new pods **and evicts already-running non-tolerating pods** (immediately, or after `tolerationSeconds` if the toleration sets one).
- A pod with no toleration can still land on *other, untainted* nodes - the taint only affects scheduling onto *that* node.

### nodeSelector vs Node Affinity
- `nodeSelector` - flat `key: value` equality map on the pod spec. AND-only across keys, no operators, no OR logic. Simple but inflexible.
- Node Affinity (`spec.affinity.nodeAffinity`) - same idea, much more expressive:
  - `requiredDuringSchedulingIgnoredDuringExecution` - hard rule, pod won't schedule unless matched (supports `In`, `NotIn`, `Exists`, `Gt`, `Lt` operators, and OR-able `nodeSelectorTerms`).
  - `preferredDuringSchedulingIgnoredDuringExecution` - soft rule with a `weight`, scheduler scores nodes but isn't blocked by it.
  - **"IgnoredDuringExecution" applies to both** - if a node's label changes *after* the pod is already running, the pod is NOT evicted either way. (A `RequiredDuringSchedulingRequiredDuringExecution` variant that *would* evict exists but isn't GA - rarely used.)

### Taints+Tolerations vs Node Affinity - when to combine
- Taints/tolerations *repel* everyone except pods that tolerate - doesn't stop other pod types from being scheduled there if the cluster has room and no better fit.
- Node affinity *attracts* a pod to specific nodes but doesn't stop other pods from landing there too.
- Combine both to truly **dedicate** a node to one workload: taint the node (keeps everything else off) + add required node affinity on the workload's pods (keeps it from landing anywhere else). This is the standard pattern for e.g. GPU nodes.

## Key commands
```bash
# taint / untaint a node
kubectl taint nodes my-cluster-control-plane dedicated=gpu:NoSchedule
kubectl taint nodes my-cluster-control-plane dedicated=gpu:NoSchedule-   # remove (trailing -)

# label a node (used by nodeSelector / node affinity)
kubectl label node my-cluster-control-plane disktype=ssd --overwrite

# inspect
kubectl describe node my-cluster-control-plane | grep -A2 Taints
kubectl get nodes --show-labels
kubectl get pod <name> -o wide          # check which node it landed on / Pending
kubectl describe pod <name> | grep -A5 Events   # see WHY it's Pending
```

## Practice YAMLs
- `pod-no-toleration.yaml` - no toleration, taint blocks it -> stays `Pending` (verified on `my-cluster`)
- `pod-with-toleration.yaml` - tolerates `dedicated=gpu:NoSchedule` -> schedules fine (verified)
- `pod-nodeselector.yaml` - `nodeSelector: {disktype: ssd}` + the toleration (needs both, since the only node is tainted) (verified)
- `pod-node-affinity.yaml` - required (`disktype in [ssd, nvme]`) + preferred node affinity, same toleration needed (verified)

## Gotchas / mistakes I made
- Mixed up `PreferNoSchedule`'s direction at first - it means "prefer to **avoid** this node," not "prefer to schedule here." Easy to misread because of the double negative in the name.
- Almost described `requiredDuringScheduling` / `preferredDuringScheduling` as if one applied "during scheduling" and the other "during execution" - they're actually two independent rule strengths, and **both** currently say `IgnoredDuringExecution` (label changes after the pod is running don't trigger eviction either way).
- On a single-node cluster, `nodeSelector`/affinity pods still need the taint's toleration too, or they stay `Pending` for a *different* reason (the taint) even though the label matches - easy to misdiagnose which rule is blocking the pod. Always `kubectl describe pod` and read the Events message rather than guessing.
