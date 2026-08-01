# Monitoring Stack

## Prometheus + Grafana (via helm)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

## Port forward Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

## Grafana default creds
Username: admin
Password: prom-operator
