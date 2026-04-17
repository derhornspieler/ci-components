# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`continuous-delivery/ci-components` — the GitLab CI/CD Catalog project for this platform. Not a runtime service. It publishes reusable pipeline components that consumer projects include via `component: $CI_SERVER_FQDN/continuous-delivery/ci-components/<name>@<tag>`. The catalog browser lives at `/explore/catalog` on the GitLab instance.

Current line: **v4.x** (3-env model: `dev / staged / prod`, platform context + credentials sourced from Vault).

## Session identity (ci-components side)

This repository has two coordinating Claude Code sessions: **Alice** (this side, `admin.user`, uses `~/.config/glab-cli-alice`) and **Frank** (`dev.user`). They communicate via comments on GitLab issues. When posting comments via `glab issue note create` / `glab mr note create`, always identify as **"Alice (ci-components team)"** in the body — the counterpart's Claude session needs unambiguous attribution to apply the concurrence rule.

## Component architecture (v4)

Ten templates under `templates/<name>/template.yml`:

- **Shared (chain-included, not used directly by consumers)**
  - `platform` — fetches platform endpoints from Vault (`kv/platform/cluster-context`), defines language-detect anchors, rules, artifacts, package-repo hydration
  - `vault-auth` — JWT login, cosign key fetch, SSH deploy key setup
- **Leaf components (per-stage)**: `pre-check`, `lint`, `test`, `build`, `scan`, `promote`, `deploy-gates`
- **Aggregate**: `pipeline` — chain-includes all 7 leaves with wired stages and `needs:`. Consumers normally include only `platform` + `pipeline`.

Minimal consumer (canonical pattern in `examples/forge-monorepo.yml`):

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@4.0.8
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pipeline@4.0.8
    inputs:
      team: forge
      app: svc-forge
      stacks: [ { name: core, language: python, paths: ["core/**"], project_dir: core, ... } ]
```

Credentials are pulled by `platform` / `vault-auth` at job-time via JWT — **no CI/CD variables are configured per-consumer-project.**

## Release-gate pipeline (the reason this repo has CI)

Every MR runs through three gates that prevent broken catalog tags from reaching consumers. The v4.0.0 → v4.0.6 failure parade happened because previous CI only ran `yamllint`; the gates below are the fix. Details in `scripts/release-gate/README.md`.

| Gate | Job | Fires when | Catches |
|------|------|-----------|---------|
| #1 | `static-render` | every MR | YAML parse, dangling `variables:` keys, `$[[ inputs.X ]]` referring to undeclared inputs, jobs missing `tags:` (our runners reject untagged) |
| #2 | `consumer-lint` | MR changes `CHANGELOG.md` or `templates/**` | catalog-URL resolution (wrong dir name, chain-include version drift, hidden-component visibility) via an ephemeral `rc-<sha>` tag against the real catalog |
| #3 | `prep-rc-tag` → `consumer-runtime` → `cleanup-rc-tag` | same rules as #2 | runtime bugs in a real consumer pipeline via GitLab native multi-project trigger (`trigger:project: continuous-delivery/ci-components-smoketest` with `strategy: depend`). `cleanup-rc-tag` is `when: always` so the `rc-*` tag is deleted regardless of outcome |

A CHANGELOG bump is the release-candidate signal that fires #2/#3. `rc-*` tags never appear in the stable catalog; only real semver tags cut after merge produce a `create-release` job.

Consumer patterns linted by gate #2 live in `tests/consumer-patterns/*.gitlab-ci.yml` (monorepo, python, typescript, go). `RC_VERSION` is a placeholder that `lint-consumer-pattern.sh` rewrites to the pushed rc tag.

## GitHub mirror

The `sync-to-github` job runs on `main` pushes. It creates a **single orphan commit** (no history), strips `.gitlab-ci.yml`, `.claude/`, `memory/`, and runs `sed` PII replacement on every text file (domain, user names) before force-pushing to GitHub. The PII allow-list is inline in `.gitlab-ci.yml:259-275`. If you add a new user/domain reference anywhere in tracked files, update the sed list there too or it will leak.

## Issue ledger & two-party concurrence

`scripts/gitlab-ops/` — ledger-driven tracker for cross-team work on this repo. Active items sit in `active_watch.json`; the watcher re-reads it every 60s. Closed issues auto-prune. The append-only audit log (`tracked_items_history.jsonl`) is gitignored.

**CLI** (always via `glab-cli-alice`):
```
./scripts/gitlab-ops/platform-track.sh list
./scripts/gitlab-ops/platform-track.sh status       <repo> <iid>
./scripts/gitlab-ops/platform-track.sh add-watch    <issue|mr> <repo> <iid> [reason]
./scripts/gitlab-ops/platform-track.sh remove-watch <issue|mr> <repo> <iid>
./scripts/gitlab-ops/platform-track.sh close-issue  <repo> <iid> [--force]
./scripts/gitlab-ops/platform-track.sh close-mr     <repo> <iid> [--force]
```

**Watcher**: run `./scripts/gitlab-ops/watcher.sh` as a Monitor task — every stdout line becomes a session notification (new issues, new comments, state transitions).

**Concurrence rule** (enforced by `close-issue` unless `--force`): a `.platform_users[]` member **and** a non-platform user have each posted a non-system comment; each side's most recent comment contains an agreement keyword (`ok to close | confirmed | verified | lgtm | all good | works | closing | merged | resolved | fixed end-to-end | good to go`); and the last 5 comments contain no objection keyword (`blocked | still failing | still broken | regression | wait | do not close | premature | not ready`).

**Hard rules for cross-team issues:**
- Never put `Fixes #N` / `Closes #N` / `Resolves #N` in MR descriptions — GitLab auto-closes on merge, bypassing concurrence. Use `Refs #N`.
- Never call `glab issue close` directly; always go through `platform-track.sh close-issue` so the rule runs.

## Local commands

```bash
# Lint templates (mirrors the `validate` CI job)
yamllint -c .yamllint.yml templates/

# Run gate #1 locally (needs ruamel.yaml)
python3 -c "import ruamel.yaml" || pip install ruamel.yaml
bash scripts/release-gate/static-render.sh

# Lint one consumer pattern against an already-pushed rc tag
bash scripts/release-gate/lint-consumer-pattern.sh tests/consumer-patterns/monorepo.gitlab-ci.yml rc-<sha>
```

Gates #2 and #3 require the smoketest project, Vault, and `SMOKETEST_*` tokens — they only run meaningfully in the pipeline, not locally.

## Gotchas (learned the hard way, baked into gate #1)

- **Every job must declare `tags:`** — both runners in the target cluster have `run_untagged: false`, so untagged jobs sit pending forever with no diagnostic. Leaves expose `runner_tags` (default `["shared"]`) and heavy jobs expose `heavy_runner_tags` (default `["shared", "compute"]`).
- **`$[[ inputs.X ]]` interpolates in the scope of the template that contains the literal text.** Don't put an anchor referencing `inputs.stacks` inside `platform` (only leaves declare `stacks`). Gate #1 catches this.
- **Don't pass array inputs through a heredoc into a YAML block scalar.** GitLab does not re-indent multi-line input values to match the surrounding scalar; the second line lands at column 0 and breaks the parse. v4.0.8 fixed this by passing through `variables:` (JSON-serialized) and writing to disk via shell `printf`.
- **The `| json` cleanup regex used in v4.0.4 removed surrounding `variables:` blocks even when sibling variables remained** — every template must still parse under a strict YAML loader, which is exactly what gate #1 verifies.

## Memory layout

Project memory lives at `/home/rocky/.claude/projects/-home-rocky-data-ci-components/memory/` (Alice identity, comment-signing rule, ledger system notes). Bootstrap script: `bootstrap-claude-memory.sh ci-components` if the tree is ever missing.
