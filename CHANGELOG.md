# Changelog

## v4.0.14 — 2026-04-17

### Changed

- Smoketest fixture: all `when: never` suppressions removed. Gate-3
  now exercises the full pipeline-aggregate end-to-end (pre-check +
  lint + test + build + scan + promote) with zero overrides.
- `push-rc-tag.sh`: falls back to `CI_COMMIT_SHA` when source branch
  is deleted before the MR pipeline finishes (race condition fix from
  MR !81).

## v4.0.13 — 2026-04-17

### Fixed

- **`pre-check:license-headers` scans .git/ on repos with no source
  files** (ci-components#3 note 3867, reported by forge). When
  `git ls-files '*.py' '*.go' '*.ts' '*.js'` returned empty (repo has
  no source files matching those globs), `xargs grep -rL` ran with no
  file arguments and fell back to scanning the entire working directory
  recursively — including `.git/` internals. Fix: check if git ls-files
  produced output; if empty, skip with exit 0.

## v4.0.12 — 2026-04-17

### Fixed

- **`scan:image` fails on trivy rego policy parsing errors**
  (ci-components#3 note 3841, reported by forge). `trivy config .`
  scanned the repo working directory for IaC misconfigurations and hit
  broken upstream AWS rego policies bundled with trivy v0.58.1 —
  unrelated to container image scanning. Removed `trivy config .` from
  `scan:image`; replaced with `trivy image --scanners vuln,secret` to
  scope to vulnerability + secret scanning only (the actual purpose of
  this job).

## v4.0.11 — 2026-04-16

### Fixed

- **`pre-check:license-headers` non-deterministic false positives**
  (ci-components#3 note 3787, reported by forge). The `find | while
  head | grep` loop raced with K8s ephemeral volume filesystem on
  fresh pod checkout — `find` started traversing before all file
  contents were flushed, so `head -5` intermittently read empty/
  truncated files. Three consecutive runs of the same commit flagged
  different files, all of which had valid headers.
  Fix: replaced `find` with `git ls-files '*.py' '*.go' '*.ts' '*.js'
  | xargs grep -rL ...`. Reads from git's index (consistent post-
  checkout) rather than the filesystem, eliminating the race.

## v4.0.10 — 2026-04-16

### Fixed

- **`pre-check:commitlint` fails on private-CA cert verify**
  (ci-components#3 note 3757, reported by forge). `git fetch origin
  <target_branch>` hit `SSL certificate OpenSSL verify result: unable
  to get local issuer certificate` because the `commitlint_image`
  (node:20-alpine) ships with the public CA bundle only and this job
  doesn't chain-include `.fetch-platform-context` (which handles CA
  trust). Fix: inline the AegisGroup CA via heredoc + `apk add
  ca-certificates` + `update-ca-certificates` before the git fetch.

- **`pre-check:secrets` false-positives on external-secrets.io CRs**
  (ci-components#3 note 3757). gitleaks' `kubernetes-secret-yaml` rule
  flagged `ExternalSecret` / `SecretStore` / `ClusterSecretStore` CRs
  even though those CRs only **reference** secrets (no material on
  disk). Fix: at runtime, auto-detect files containing `kind:
  ExternalSecret|SecretStore|ClusterSecretStore` and add them to a
  generated `/tmp/gitleaks.toml` `[allowlist].paths`. Consumer-shipped
  `.gitleaks.toml` / `.gitleaks.yaml` takes precedence if present.

## v4.0.9 — 2026-04-15

### Fixed

- **`variables: STACKS_INPUT: $[[ inputs.stacks ]]`** (v4.0.8) doesn't
  work either: GitLab rejects array inputs in variable values with
  "variable definition must be either a string or a hash." Caught by
  Gate #2 (consumer-lint with rc tag) — first end-to-end exercise of
  that gate, working as designed.
  Reverted to heredoc-based `$[[ inputs.stacks ]]` rendering inside a
  `script:` block, which IS supported. Added mandatory `.dump-stacks`
  call immediately after so /tmp/stacks.yml is always visible in the
  trace if anything else surfaces.
- pre-check now writes `/tmp/ignore.yml` and `/tmp/exclude.yml` via
  the same heredoc pattern (those were also array inputs going
  through the broken `variables:` route).

## v4.0.8 — 2026-04-15

### Fixed

- **`$[[ inputs.stacks ]]` heredoc rendered unparseable YAML** (#3,
  Bug A). The v4.0.1–v4.0.7 anchors wrote the stacks array via a
  quoted heredoc. GitLab's input interpolation for array values does
  NOT re-indent multi-line content to match the surrounding YAML
  block scalar, so the rendered file's second line landed at column 0
  and broke the block-scalar parse before yq ever saw it.
  Fix: pass the stacks array through a GitLab CI `variables:` entry
  (GitLab serializes array inputs as JSON in string context), then
  write the value to disk via shell `printf` — no YAML interpolation,
  no heredoc indent problem, no yq install.

### Added

- `.dump-stacks` anchor that emits `cat -A /tmp/stacks.yml` to the
  job trace so the rendered content of any future stacks-like input
  is always visible.

### Removed

- `.install-yq` and `.convert-stacks-json` anchors (replaced by
  `.materialize-stacks`, which does not need yq).

## v4.0.7 — 2026-04-15

### Fixed

- **No runner accepts untagged jobs.** Every job emitted by v4.0.x
  templates was untagged, but both online runners in the target cluster
  (`gitlab-runner-shared`, `gitlab-runner-terraform`) have
  `run_untagged: false`. Pipelines sat `pending` indefinitely with no
  diagnostic. Blocker #4 on #1.

### Added

- `runner_tags` input on every leaf + `pipeline` aggregate, default
  `["shared"]`. All light jobs (`pre-check:*`, `lint:*`, `test:*`,
  `promote`, `deploy-gates:*`) now emit `tags: $[[ inputs.runner_tags ]]`.
- `heavy_runner_tags` input on `build` / `scan` + `pipeline` aggregate,
  default `["shared", "compute"]`. `build:image` and `scan:image` emit
  `tags: $[[ inputs.heavy_runner_tags ]]` so large container builds
  steer to compute-pool runners.
- Consumers who need different tags override via the `pipeline` input
  (single point of control).

## v4.0.6 — 2026-04-15

### Fixed

- **Orphaned `variables:` keys** in `test/`, `build/`, `scan/`, and
  `promote/` templates. The `| json` cleanup regex in v4.0.4 removed
  the enclosing `variables:` block even when sibling variables still
  needed it (DEFAULT_COV, TEAM, SEVERITY, STORAGE_DRIVER, BUILDAH_FORMAT,
  APP, APPDEPS_REPO), leaving them dangling under the wrong keys and
  failing YAML parse.
- Every template now parses cleanly under a strict YAML loader.

### Process

- This is the **sixth** v4 tag blocking consumers. Previous smoketest
  used `local:` includes which don't exercise the catalog resolver.
  Adding a real consumer-flow guardrail is the next priority — see #1
  discussion.

## v4.0.5 — 2026-04-15

### Fixed

- **Platform template `$[[ inputs.stacks ]]` scope error** from v4.0.4.
  The `.materialize-stacks-json` anchor lived inside the platform
  template and referenced `$[[ inputs.stacks ]]`, but platform's
  `spec.inputs` doesn't declare `stacks` (only leaves do). GitLab
  interpolates `$[[]]` in the scope of the template that contains the
  literal text, so platform's anchor failed with `unknown interpolation:
  stacks in inputs.stacks`.
  Split the anchor into `.install-yq` (yq install only, no `$[[]]`,
  safely callable from anywhere) and `.convert-stacks-json` (reads
  `/tmp/stacks.yml`, no `$[[]]`). Each leaf now writes
  `/tmp/stacks.yml` inline via its own `$[[ inputs.stacks ]]` heredoc
  (scoped to the leaf's inputs) between the two anchor calls.

### Updated

- `examples/forge-monorepo.yml` and `examples/identity-webui.yml`
  bumped to `@4.0.5`.
- Chain-includes bumped to `@4.0.5`.

## v4.0.4 — 2026-04-15

### Fixed

- **`| json` pipe in lint/test/build/scan/promote** (follow-up to v4.0.1
  which only fixed pre-check). Same class of bug: every remaining leaf
  template's `variables:` block used `$[[ inputs.stacks | json ]]`, which
  is not a real GitLab CI input pipe function. 10 sites affected. Replaced
  with a new reusable `.materialize-stacks-json` anchor in the platform
  template that renders the input as YAML, converts to JSON via `yq`, and
  exports `STACKS_JSON`. yq installs portably (apk/apt/curl) so the anchor
  works across Alpine, Debian-slim, and language-specific images.
- Bumped chain-includes to `@4.0.4`.

## v4.0.3 — 2026-04-15

### Fixed

- **Shared component URL mismatch (root cause of v4.0.0/4.0.1/4.0.2
  "content not found" for consumers).** The shared components lived
  at `templates/_platform/` and `templates/_vault-auth/`, so the
  catalog published them as `_platform@X.Y.Z` and `_vault-auth@X.Y.Z`.
  But every sibling template referenced them as `platform@X.Y.Z` and
  `vault-auth@X.Y.Z` (without underscore). Every chain-include failed
  to resolve, which surfaced to consumers as a totally unusable
  catalog. Renamed the directories to drop the underscore so the
  catalog URL matches what the templates already reference.
- Bumped chain-includes to `@4.0.3`.

### Note on v4.0.0–v4.0.2

All three prior v4 tags are structurally broken by the underscore
mismatch above and should not be used. v4.0.3 is the first usable v4
catalog release.

## v4.0.2 — 2026-04-15

### Fixed

- **Chain-include version drift.** v4.0.1 patched the bare pre-check
  template but `pipeline/template.yml` and every other aggregate
  chain-included leaves at `@4.0.0`, so consumers bumping to
  `pipeline@4.0.1` still picked up broken pre-check transitively.
  Bumped every internal `ci-components/<name>@4.0.0` reference in
  `templates/*/template.yml` to `@4.0.2`. Also updated the usage
  examples in each leaf's README so developers copy-paste the current
  version.

## v4.0.1 — 2026-04-14

### Fixed

- **`pre-check/template.yml`**: `STACKS_JSON` / `IGNORE_JSON` /
  `EXCLUDE_JSON` variables used `$[[ inputs.<x> | json ]]`, but `json`
  is not a built-in GitLab CI input pipe function. Every consumer that
  exercised pre-check failed at lint time. Replaced with heredoc YAML
  rendering of the input arrays + in-shell `yq -o=json` conversion.
  Fixes #1.

### Added

- **`tests/smoketest-pre-check.gitlab-ci.yml`** + new `smoketest` stage
  in catalog CI: child pipeline that includes pre-check via
  `local:` and passes representative array inputs. Catches unknown
  input-function bugs at catalog build time, before consumers see them.

## v4.0.0 — 2026-04-12

Ground-up redesign. See
[docs/superpowers/specs/2026-04-12-minimalcd-v4-platform-context.md](../../../docs/superpowers/specs/2026-04-12-minimalcd-v4-platform-context.md)
in `harvester-rke2-svcs` for the full spec.

### Breaking

- Three-environment model (`dev / staged / prod`). `test` collapsed into `dev`.
- Platform context now lives in Vault (`platform/cluster-context`) — no more
  per-component `harbor_registry` / `vault_addr` input defaults.
- Credentials pulled from Vault (`platform/ci-robots/*`, `platform/cosign/*`);
  CI group vars removed.
- Language handling replaced by explicit `stacks:` declaration + validation.
- `staged` is now a prod mirror. Enforcement is CI-side via `conftest` + Rego
  (Kyverno not installed on the cluster).
- Component surface: 2 shared (`_platform`, `_vault-auth`) + 7 leaf
  (`pre-check`, `lint`, `test`, `build`, `scan`, `promote`, `deploy-gates`)
  + 1 aggregate (`pipeline`).
- v3 leaf components removed from main.

### Added

- `_platform` — platform endpoint fetch from Vault, language-detect anchors,
  rules anchors, artifact schemas, package-repo hydration
- `_vault-auth` — JWT login, cosign sign/verify key fetch, SSH deploy key setup
- `pre-check:stack-validate` — enforces spec §7 stack declaration
- `deploy-gates/policies/staged-mirror-contract.rego` — CI-side enforcement of
  the spec §4 staged = prod mirror contract, with test fixtures
- `pipeline` aggregate component — one-include app pipeline
- `examples/forge-monorepo.yml`, `examples/identity-webui.yml` — v4 consumer
  examples

### Deferred

- `gate:perf-regression` is a placeholder until the Argo Workflow ships
- `gate:argocd-diff` is a stub; full ArgoCD API call follows in a follow-up MR
