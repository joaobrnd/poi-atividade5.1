#!/usr/bin/env bash
# Deploy das tres aplicacoes - executar DENTRO da VM
set -euo pipefail

kubectl apply -f "$(dirname "$0")/../k8s/"
kubectl rollout status deployment/cpu-service     -n poi
kubectl rollout status deployment/memory-service  -n poi
kubectl rollout status statefulset/io-service     -n poi

kubectl get all -n poi

echo "--- verificacao local (NodePorts publicados na VM)"
curl -s localhost:30001/health; echo
curl -s localhost:30002/health; echo
curl -s localhost:30003/health; echo
