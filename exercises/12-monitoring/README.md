# monitoring

## What I learned

### Architecture: metrics are PULLED, never pushed
Prometheus reaches out on a timer (~30s) and scrapes `/metrics` from every target it knows about. Apps never
send data anywhere - they just passively expose a text endpoint and wait to be asked. Grafana stores zero
metrics itself - every dashboard panel fires a live PromQL query at Prometheus's HTTP API on load/refresh.

```
 Your app's Pod
   exposes GET /metrics (passive)
        ^
        | scraped every ~30s
        |
 Prometheus server <----- scrape targets configured by ----- ServiceMonitor CRD
   |                                                           (watched + applied by
   | stores samples in its own local TSDB                      Prometheus Operator)
   | evaluates alert rules continuously
   |
   +---> firing alerts ---> Alertmanager ---> Slack/email/etc.
   |
   | PromQL query, live, over HTTP - on every dashboard load
   v
 Grafana (no storage of its own)
```

### Component roles
| Component | Job |
|---|---|
| node-exporter | DaemonSet, 1/node. Machine-level metrics (CPU/mem/disk) straight from the kernel. |
| kube-state-metrics | Kubernetes *object state* as metrics (desired vs available replicas, restart counts) - reads the API server, not pods. |
| Prometheus Operator | Translates CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`) into real Prometheus scrape config automatically - never hand-edit `prometheus.yml`. |
| Prometheus server | Does the actual scraping, stores samples in local TSDB, evaluates alert rules. |
| Alertmanager | Receives firing alerts, dedups/groups/routes, sends notifications. Not involved in dashboards. |
| Grafana | Pure query+viz layer. Datasource = Prometheus's HTTP API. |

### Logs vs metrics - this stack is METRICS ONLY
Prometheus/Grafana here never handle log lines. Actual log search in Grafana needs a second, parallel stack:
Loki (stores logs) + Promtail/Alloy (DaemonSet that tails container logs, ships to Loki) + a second Grafana
datasource queried with LogQL instead of PromQL. Not installed - metrics only for this pass.

## Key commands
```bash
# install the whole stack in one shot
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# access
kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80        # Grafana UI
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090   # Prometheus UI + /targets

# verify a ServiceMonitor got picked up
# -> browser: http://localhost:9090/targets, look for your job, State: UP
```

## Practice YAMLs
- `example-app.yaml` - Deployment + Service for `quay.io/brancz/prometheus-example-app` (has a built-in `/metrics` endpoint, zero instrumentation needed - standard demo app from the Prometheus Operator docs)
- `example-app-servicemonitor.yaml` - wires that Service into Prometheus's scrape config

## Gotchas / mistakes I made
- **`ServiceMonitor` needs `metadata.labels.release: <helm-release-name>`** (`monitoring` here) to match the
  Prometheus CR's own selector. Miss this label and Prometheus silently ignores the ServiceMonitor forever -
  no error anywhere, it just never shows up in Targets.
- `endpoints[].port` in a ServiceMonitor must match the Service's **port name** (e.g. `web`), not the port number.
- KinD's Prometheus/Grafana container images don't include `curl` or `wget` - can't `kubectl exec` in and hit
  the API directly for a quick check. Use the `/targets` page in the browser via port-forward instead.
- **Leaked a real credential into this very file.** Ran the `kubectl get secret ... | base64 -d` command meant
  for the terminal, but the output landed in this README (open in the IDE at the same time) instead - and it
  got committed and pushed to a *public* GitHub repo before being caught. Low real-world risk here (Grafana's
  only reachable via `kubectl port-forward` on localhost, not internet-exposed) but it's the exact "never
  commit secrets to Git" lesson from topics 3/4, happening for real. Fix: rotate the password
  (`kubectl patch secret ... admin-password`), never let command output land in an open editor tab, and
  double-check `git diff` before committing anything that touched a terminal command involving `secret`.
