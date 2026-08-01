#!/bin/bash
CLUSTER_NAME=${1:-k8s-lab}
echo "🗑️  Deleting KinD cluster: $CLUSTER_NAME"
kind delete cluster --name $CLUSTER_NAME
echo "✅ Done"
