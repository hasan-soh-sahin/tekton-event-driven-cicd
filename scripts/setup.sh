#!/usr/bin/env bash
set -euo pipefail
TOKEN="${WEBHOOK_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  echo "Set WEBHOOK_TOKEN (use a unique random secret) before running." >&2
  exit 1
fi
kubectl apply -f k8s/00-namespace-rbac.yaml
kubectl -n data-platform-ci create secret generic gitlab-webhook-secret \
  --from-literal=secretToken="$TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/10-listener-binding-template.yaml
kubectl apply -f k8s/20-trigger-customer-scoring.yaml
kubectl apply -f k8s/20-trigger-fraud-detection.yaml
kubectl apply -f k8s/30-demo-pipeline.yaml
kubectl -n data-platform-ci get eventlisteners,triggers,pipelines
