# ArgoCD

## Install
sh install.sh

## CMDS
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

## Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:80

## Access
http://localhost:8080
Username: admin
