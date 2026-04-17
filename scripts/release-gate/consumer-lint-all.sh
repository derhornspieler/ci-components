#!/usr/bin/env bash
# consumer-lint-all.sh — Gate #2.
# Push an ephemeral rc-* tag, lint every consumer pattern against it
# via the real catalog URL, delete the rc tag regardless of outcome.
#
# Catches catalog-URL resolution bugs (directory-name mismatch,
# chain-include version drift, catalog publish issues, hidden component
# visibility) — everything that #1 can't see because #1 lints against
# the branch, not the catalog-published version.
#
# Runs on MR when CHANGELOG.md has changed (release-candidate signal).
set -euo pipefail

: "${CI_SERVER_URL:?}"
: "${CI_PROJECT_ID:?}"
: "${SMOKETEST_API_TOKEN:?}"
: "${CI_COMMIT_SHA:?}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"

TAG="$("${here}/push-rc-tag.sh")"
trap '"${here}/cleanup-rc-tag.sh" "${TAG}" || true' EXIT

# GitLab needs a moment to publish the tag to the catalog index.
sleep 10

failed=0
total=0
for pattern in "${root}"/tests/consumer-patterns/*.gitlab-ci.yml; do
  total=$((total + 1))
  if ! "${here}/lint-consumer-pattern.sh" "${pattern}" "${TAG}"; then
    failed=$((failed + 1))
  fi
done

echo "[consumer-lint] ${total} patterns linted against @${TAG}, ${failed} failed"
[[ ${failed} -eq 0 ]]
