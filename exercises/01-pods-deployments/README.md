# pods-deployments

## What I learned
- A Pod is the smallest unit: one or more containers sharing network and storage.
- A bare Pod is not managed. Delete it and it stays gone.
- A Deployment creates a ReplicaSet, which creates and maintains the Pods (self-healing).
  `Deployment -> ReplicaSet -> Pods`, linked by `ownerReferences` and the `app` label (plus `pod-template-hash`).
- Deleting a Deployment cascades: the ReplicaSet and all its Pods are deleted too.
- Scaling changes the ReplicaSet's replica count; new Pods appear immediately.
- First run of an image is slow (`ContainerCreating`) because the image must be pulled.

## Key commands
```bash
kubectl create namespace refresh-01
kubectl apply -n refresh-01 -f deployment.yaml
kubectl get deploy,rs,pods -n refresh-01
kubectl get pods -n refresh-01 --show-labels
kubectl delete pod <name> -n refresh-01        # Deployment recreates it
kubectl scale deploy web -n refresh-01 --replicas=5
kubectl describe pod <name> -n refresh-01      # see "Controlled By"
kubectl delete deploy web -n refresh-01        # cascades to RS and Pods
```

## Practice YAMLs
- See .yaml files in this folder

## Gotchas / mistakes I made
- Thought the Pod "wasn't coming up": it was just pulling the image. Check `kubectl get events` or `describe`.
- A deleted bare Pod is not recreated; only Deployment-managed Pods are.
- `kubectl get pods` without `-n` shows the `default` namespace, not the one I'm working in.
