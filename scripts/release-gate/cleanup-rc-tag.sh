#!/usr/bin/env bash
# cleanup-rc-tag.sh — delete an rc-* tag (pass/fail, we never keep it).
# Safe to call multiple times.
set -euo pipefail

: "${CI_SERVER_URL:?}"
: "${CI_PROJECT_ID:?}"
: "${SMOKETEST_API_TOKEN:?}"

TAG="${1:?tag name required}"

log() { echo "[rc-tag] $*" >&2; }
log "deleting ${TAG}"

code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 30 \
  --header "PRIVATE-TOKEN: ${SMOKETEST_API_TOKEN}" \
  --request DELETE \
  "${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}/repository/tags/${TAG}")"

case "${code}" in
  204|404) log "deleted (or already gone)"; exit 0 ;;
  *)       log "FAIL delete ${TAG} (HTTP ${code})"; exit 1 ;;
esac
