# External Secrets Operator

## Install via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

## Verify
kubectl get pods -n external-secrets
