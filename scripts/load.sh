#!/usr/bin/env bash
# Sends parallel CPU-heavy requests so the HPA scales the deployment out.
# Usage: ./scripts/load.sh [base_url] [duration_seconds] [workers]
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
DURATION="${2:-120}"
WORKERS="${3:-8}"
END=$((SECONDS + DURATION))

echo "Load: ${WORKERS} workers against ${BASE_URL} for ${DURATION}s"
echo "Watch it scale in another terminal: kubectl -n status-api get hpa,pods -w"

worker() {
  while [ "$SECONDS" -lt "$END" ]; do
    curl --silent --output /dev/null "${BASE_URL}/api/work?ms=200" || true
    curl --silent --output /dev/null "${BASE_URL}/api/quote" || true
  done
}

for _ in $(seq "$WORKERS"); do
  worker &
done
wait
echo "Load finished."
