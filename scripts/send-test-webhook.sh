#!/usr/bin/env bash
set -euo pipefail
REPO="${1:-customer-scoring}"
BRANCH="${2:-main}"
case "$REPO" in
  customer-scoring|fraud-detection|other-repo) ;;
  *) echo 'Usage: scripts/send-test-webhook.sh [customer-scoring|fraud-detection|other-repo] [main|dev]' >&2; exit 2;;
esac
: "${WEBHOOK_TOKEN:?Please export WEBHOOK_TOKEN}"
URL="${LISTENER_URL:-http://localhost:8080}"
BODY="$(sed -e "s|__REPO__|$REPO|g" -e "s|__BRANCH__|$BRANCH|g" examples/push-template.json)"
printf '%s\n' "Sending $REPO on $BRANCH to $URL"
curl --fail-with-body -sS -i -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H 'X-Gitlab-Event: Push Hook' \
  -H "X-Gitlab-Token: $WEBHOOK_TOKEN" \
  --data-binary "$BODY"
echo
