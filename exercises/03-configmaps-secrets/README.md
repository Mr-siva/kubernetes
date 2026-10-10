# configmaps-secrets

## What I learned
- ConfigMap = non-sensitive key/value config. Secret = sensitive values (base64-encoded, NOT encrypted).
- A Pod can consume both as env vars (`env.valueFrom.configMapKeyRef`) or as mounted files (`volumes` + `volumeMounts`).
- Each key becomes one file in the mount directory (`/etc/config/APP_MODE`, `/etc/secrets/DB_PASSWORD`).
- **Mounted files update automatically** after a ConfigMap change (kubelet sync, up to ~1 min).
  **Env vars do NOT update** until the container restarts. (Files mounted with `subPath` never update.)
- `stringData` lets me write plain text; k8s stores it as base64 under `data`.
- `kubectl apply` stores the original YAML in the `last-applied-configuration` annotation, so a plaintext
  Secret value is visible there too. Never commit Secret YAML to Git; use External Secrets (topic 4).
- Name matching: `volumes.configMap.name` / `volumes.secret.secretName` / `configMapKeyRef.name` must equal the object name;
  `volumeMounts.name` must equal a `volumes.name`.

## Key commands
```bash
kubectl get configmap app-config -n refresh-03
kubectl describe secret app-secret -n refresh-03          # shows size only, not value
kubectl get secret app-secret -n refresh-03 -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
kubectl exec -n refresh-03 cfg-pod -- sh -c 'echo "env=$APP_MODE"; echo "file=$(cat /etc/config/APP_MODE)"'
kubectl delete pod cfg-pod -n refresh-03 && kubectl apply -f pod.yaml   # restart to refresh env vars
```

## Practice YAMLs
- namespace.yaml, configmap.yaml, secret.yaml, pod.yaml

## Gotchas / mistakes I made
- Git Bash turned `/etc/config` into `C:/Program Files/Git/etc/config`: `export MSYS_NO_PATHCONV=1` (in ~/.bashrc) or use `//etc/config`.
- Pasting terminal output back into the shell runs it as commands ("command not found"); paste only commands.
- `apply` said "unchanged" because the edit wasn't saved in the editor; check the file on disk.
- A bare Pod isn't recreated when deleted; re-apply the YAML to restart it.
