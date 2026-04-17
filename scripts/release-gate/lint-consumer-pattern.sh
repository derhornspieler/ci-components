#!/usr/bin/env bash
# lint-consumer-pattern.sh — validate a single consumer pattern file
# against a specific catalog version via GitLab's ci/lint API.
#
# Usage: lint-consumer-pattern.sh <pattern.gitlab-ci.yml> <version>
#   e.g. lint-consumer-pattern.sh tests/consumer-patterns/python.gitlab-ci.yml rc-abc1234
#
# Requires:
#   CI_SERVER_URL         — e.g. https://gitlab.example.com
#   CI_PROJECT_ID         — the ci-components project ID (lint context)
#   SMOKETEST_API_TOKEN   — PAT or job token with read_api on the
#                           ci-components project (enough for ci/lint)
set -euo pipefail

PATTERN_FILE="${1:?path to consumer pattern .gitlab-ci.yml required}"
VERSION="${2:?version tag required (e.g. rc-abc1234 or 4.0.6)}"

: "${CI_SERVER_URL:?must be set (e.g. https://gitlab.example.com)}"
: "${CI_PROJECT_ID:?must be set (numeric id of continuous-delivery/ci-components)}"
: "${SMOKETEST_API_TOKEN:?must be set (PRIVATE-TOKEN with read_api)}"

log() { echo "[lint-consumer] $*" >&2; }

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT
sed "s|RC_VERSION|${VERSION}|g" "${PATTERN_FILE}" > "${rendered}"

log "linting $(basename "${PATTERN_FILE}") against @${VERSION}"

# GitLab CI lint API: POST content as JSON field.
response="$(curl -sS --max-time 30 \
  --header "PRIVATE-TOKEN: ${SMOKETEST_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --request POST \
  --data "$(jq -n --arg c "$(cat "${rendered}")" '{content: $c, dry_run: true, ref: env.VERSION}')" \
  "${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}/ci/lint" || echo '{}')"

valid="$(echo "${response}" | jq -r '.valid // false')"
if [[ "${valid}" == "true" ]]; then
  log "OK  $(basename "${PATTERN_FILE}") @${VERSION}"
  exit 0
fi

log "FAIL $(basename "${PATTERN_FILE}") @${VERSION}"
echo "${response}" | jq -r '.errors[]? // .warnings[]? // .message? // "<unknown lint error>"' | sed 's/^/  /' >&2
exit 1
