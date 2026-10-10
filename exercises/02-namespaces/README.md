# namespaces

## What I learned
- A namespace partitions names: the same Deployment/Service name can exist in team-a and team-b.
- Namespaces do NOT isolate network traffic by default (NetworkPolicy is needed for that).
- Service DNS: `<svc>` (same ns), `<svc>.<ns>`, or `<svc>.<ns>.svc.cluster.local` (cross-ns).
  Pod `/etc/resolv.conf` search path starts with its own namespace; nameserver is CoreDNS.
- ResourceQuota caps total pods / CPU / memory requests per namespace.
- Once a quota covers CPU/memory, every container must declare `requests`, or Pod creation is forbidden.
- Quotas are not retroactive: existing Pods are not rejected, they just aren't counted at creation.
- A full quota can stall a rolling update (surge Pods have no room).

## Key commands
```bash
kubectl create namespace team-a
kubectl get pods -A -l app=web
kubectl run tester -n team-a --image=busybox:1.36 --restart=Never --rm -it -- sh -c 'wget -qO- http://web.team-b.svc.cluster.local'
kubectl describe quota team-a-quota -n team-a
kubectl patch resourcequota team-a-quota -n team-a --type=merge -p '{"spec":{"hard":{"pods":"10"}}}'
kubectl describe rs -n team-a | grep -i "forbidden\|exceeded"
kubectl delete namespace team-a     # deletes everything inside
```

## Practice YAMLs
- See .yaml files in this folder

## Gotchas / mistakes I made
- `kubectl get pods` without `-n` shows `default`, not the namespace I'm working in.
- Quota error "must specify requests.cpu/memory": add `resources.requests` to the container.
- Old FailedCreate events stay in `describe` output after the fix; check timestamps.
