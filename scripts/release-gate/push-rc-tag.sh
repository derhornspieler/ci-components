#!/usr/bin/env bash
# push-rc-tag.sh — create an ephemeral rc-* tag the catalog can be
# linted against BEFORE a real semver release is cut.
#
# IMPORTANT: chain-include version drift handling.
#
# Templates reference each other via hardcoded `@4.0.X` URLs. At gate-
# test time, the candidate version (e.g. `4.0.9`) doesn't exist in the
# catalog yet — only the rc tag does. So the bare commit's chain-
# includes would resolve `pre-check@4.0.9` and fail.
#
# Fix: rewrite chain-include versions to the rc tag in a temporary
# commit, tag THAT, and use it for the gate. The rewrite is reverted
# automatically when the rc tag is deleted (the rewrite commit is
# unreachable from any branch).
#
# Steps:
#   1. Read CHANGELOG to find the candidate semver (top heading)
#   2. Clone the repo locally, sed-replace `@<candidate>` with `@<rc-tag>`
#      across templates/
#   3. Commit + push as a temporary branch
#   4. Tag the rc-* against that branch's HEAD
#   5. Delete the temporary branch
set -euo pipefail

: "${CI_SERVER_URL:?}"
: "${CI_PROJECT_ID:?}"
: "${SMOKETEST_API_TOKEN:?}"
: "${CI_COMMIT_SHA:?}"
: "${CI_PROJECT_PATH:?}"

TAG="rc-${CI_COMMIT_SHA:0:8}"
TMP_BRANCH="rc-prep-${CI_COMMIT_SHA:0:8}"

log() { echo "[rc-tag] $*" >&2; }

# Find candidate semver from CHANGELOG.md top entry
CANDIDATE="$(grep -m1 -oE '^## v?[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | sed -E 's|^## v?||')"
if [[ -z "${CANDIDATE}" ]]; then
  log "FAIL — could not parse candidate version from CHANGELOG.md"
  exit 1
fi
log "candidate version from CHANGELOG: ${CANDIDATE}"

# Clone via API token so we can push back.
# Try the branch name first; fall back to a branchless clone + checkout
# of the exact commit SHA if the branch was already deleted (happens when
# GitLab deletes the source branch on merge while the MR pipeline is
# still running).
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
CLONE_URL="https://oauth2:${SMOKETEST_API_TOKEN}@${CI_SERVER_URL#https://}/${CI_PROJECT_PATH}.git"
if ! git clone --depth 1 --branch "${CI_COMMIT_REF_NAME:-main}" \
    "${CLONE_URL}" "${WORK}/repo" >&2 2>/dev/null; then
  log "branch ${CI_COMMIT_REF_NAME:-main} not found, falling back to SHA ${CI_COMMIT_SHA}"
  git clone --no-checkout "${CLONE_URL}" "${WORK}/repo" >&2
  cd "${WORK}/repo"
  git fetch origin "${CI_COMMIT_SHA}" --depth 1 >&2 || true
  git checkout "${CI_COMMIT_SHA}" >&2
else
  cd "${WORK}/repo"
fi
git checkout "${CI_COMMIT_SHA}" >&2 || true
git checkout -b "${TMP_BRANCH}" >&2

# Rewrite chain-include versions in templates/
log "rewriting chain-includes ${CANDIDATE} -> ${TAG}"
find templates/ -name '*.yml' -o -name '*.yaml' \
  | xargs sed -i "s|/ci-components/\\([a-z_-]*\\)@${CANDIDATE}|/ci-components/\\1@${TAG}|g"

# Anything actually changed?
if git diff --quiet; then
  log "no chain-include rewrites needed (template versions already at ${TAG} or candidate not used)"
else
  git -c user.email="release-gate@ci.local" -c user.name="release-gate" \
    commit -am "rc-prep: rewrite ci-components/*@${CANDIDATE} -> @${TAG}" >&2
  git push origin "${TMP_BRANCH}" >&2
fi

PREP_SHA="$(git rev-parse HEAD)"
log "rc-prep HEAD: ${PREP_SHA}"

# Tag the (possibly rewritten) commit
resp="$(curl -sS --max-time 30 \
  --header "PRIVATE-TOKEN: ${SMOKETEST_API_TOKEN}" \
  --request POST \
  "${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}/repository/tags?tag_name=${TAG}&ref=${PREP_SHA}")"

name="$(echo "${resp}" | jq -r '.name // ""')"
if [[ "${name}" == "${TAG}" ]]; then
  log "created ${TAG} on ${PREP_SHA}"
  # Delete the prep branch immediately — only the tag needs to exist
  curl -sS --max-time 30 \
    --header "PRIVATE-TOKEN: ${SMOKETEST_API_TOKEN}" \
    --request DELETE \
    "${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}/repository/branches/${TMP_BRANCH}" \
    -o /dev/null
  echo "${TAG}"
  exit 0
fi

msg="$(echo "${resp}" | jq -r '.message // ""')"
if [[ "${msg}" == *"already exists"* ]]; then
  log "tag ${TAG} already exists — reusing"
  echo "${TAG}"
  exit 0
fi

log "FAIL to create tag: ${resp}"
exit 1
