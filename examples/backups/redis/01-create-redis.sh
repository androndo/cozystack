#!/bin/bash
# Step 01: Provision a Redis (RedisFailover) instance and seed a sentinel marker
# key used to prove the backup/restore round-trip carries the exact bytes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00-helpers.sh"

print_header "Step 01: Provision Redis '${REDIS_NAME}'"

kubectl apply -f - <<EOF
apiVersion: apps.cozystack.io/v1alpha1
kind: Redis
metadata:
  name: ${REDIS_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  resourcesPreset: nano
  size: 1Gi
  authEnabled: true
EOF

log_substep "Waiting for the Redis statefulset to be ready..."
kubectl -n "$NAMESPACE" rollout status statefulset/"rfr-${REDIS_NAME}" --timeout=300s

wait_redis_master "$REDIS_NAME"

log_substep "Writing marker ${MARKER_KEY}=${MARKER_VALUE}..."
redis_cmd "$REDIS_NAME" SET "$MARKER_KEY" "$MARKER_VALUE" >/dev/null
got=$(redis_cmd "$REDIS_NAME" GET "$MARKER_KEY")
[[ "$got" == "$MARKER_VALUE" ]] || { log_error "seed failed: read back '${got}'"; exit 1; }
log_success "Marker seeded on '${REDIS_NAME}'."

echo -e "\n${GREEN}${BOLD}Next:${NC} ./02-create-backupjob.sh"
