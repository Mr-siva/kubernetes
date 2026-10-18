# external-secrets

## What I learned

### The problem
Plain Kubernetes Secrets are only base64, and their YAML must never go into Git. The real secret
lives in AWS Secrets Manager. External Secrets Operator (ESO) copies it into the cluster as a normal
Kubernetes Secret and keeps it in sync, so Git only holds a *reference*, never the value.

### The pieces
| Piece | Who creates it | Job |
|---|---|---|
| ESO controller | Installed once (Helm), runs in `external-secrets` namespace | Watches the CRs below, authenticates to AWS, fetches values, writes the Secret |
| SecretStore / ClusterSecretStore | Me (YAML) | HOW to connect + authenticate to AWS (provider, region, credentials). SecretStore = one namespace, ClusterSecretStore = whole cluster |
| ExternalSecret | Me (YAML) | WHAT to fetch (`remoteRef`) and WHERE to store it (`target.name`) |
| Kubernetes Secret | Created and owned by ESO | The normal Secret the Pod consumes |
| Pod | Me (YAML) | Mounts the Secret as files or env vars, knows nothing about AWS |

### Flow (block diagram)
```
AWS Secrets Manager
        |
        |  Remote secret: prod/db
        v
SecretStore / ClusterSecretStore
  └── AWS provider + IAM authentication
        |
        v
ExternalSecret
  └── remoteRef: prod/db
  └── target: db-secret
        |
        v
Kubernetes Secret: db-secret
  ├── username
  └── password
        |
        v
Application Pod
  └── Reads DB credentials
```

### Inside the cluster
![ESO architecture](eso-architecture.png)

Text version:
```
 You: kubectl apply / ArgoCD (GitOps)
        |                       |
        v                       v
 ClusterSecretStore        ExternalSecret
 (how to connect + auth)   (what + where to store)
        \                       /
         v                     v
        ESO controller  (Deployment, external-secrets ns)
          1. Watch  ExternalSecret + Store CRs
          2. Auth   IAM credentials
          3. Fetch  map AWS keys -> Secret data   <----> AWS Secrets Manager
                |                                         (prod/db-password)
                v
        Kubernetes Secret  (created + owned by ESO)
                |
                v
        Pod  (volume mount /etc/secrets)

 Refresh loop: ESO re-fetches every `refreshInterval`, so rotating the value in AWS
 updates the Secret automatically.
```

### The critical name links (typo = silent failure)
```
ExternalSecret.spec.secretStoreRef.name  ==  ClusterSecretStore.metadata.name
ExternalSecret.spec.target.name          ==  Pod.volumes.secret.secretName
```

## Key commands
```bash
# install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# check the chain
kubectl get clustersecretstore fake-store
kubectl get externalsecret db-external-secret
kubectl get secret db-secret -o jsonpath='{.data.username}' | base64 -d; echo

# read the mounted files inside the pod (Git Bash needs MSYS_NO_PATHCONV=1, see gotchas)
MSYS_NO_PATHCONV=1 kubectl exec db-consumer -- cat /etc/secrets/username
```

## Practice YAMLs
- `cluster-secret-store.yaml` — ClusterSecretStore using the built-in `fake` provider (no AWS needed for local practice)
- `external-secret.yaml` — ExternalSecret pulling `username`/`password` out of the fake store's JSON blob
- `pod.yaml` — Pod mounting `db-secret` as files under `/etc/secrets`

## Gotchas / mistakes I made
- `ClusterSecretStore`/`ExternalSecret` apiVersion is `external-secrets.io/v1`, not `v1beta1` — current ESO only serves `v1` (check with `kubectl get crd clustersecretstores.external-secrets.io -o jsonpath='{.spec.versions}'` if apply ever says "no matches for kind").
- Right after `helm install`, the `cert-controller` and `webhook` pods show `0/1` for ~30s while the webhook cert is issued. `ClusterSecretStore`/`ExternalSecret` applies can fail validation until all 3 ESO pods are `1/1`.
- **Fake provider requires an exact `version` match.** Unlike a real provider (where omitting `remoteRef.version` means "latest"), the fake provider errors with `Secret does not exist` if the store entry has `version: "v1"` and the ExternalSecret's `remoteRef` doesn't also specify `version: "v1"`. This is fake-provider-specific behavior, not how AWS/Vault work.
- Git Bash rewrites absolute-looking paths (`/etc/secrets/username`) into Windows paths before they reach `kubectl exec`/`kubectl apply -f -`-style args. Prefix the command with `MSYS_NO_PATHCONV=1` when passing a container path as an argument.
