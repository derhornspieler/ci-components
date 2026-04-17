# scripts/gitlab-ops/

Ledger-driven issue/MR tracking for cross-team work on the
`continuous-delivery/ci-components` project. Same tooling shape as the
equivalent folder in `harvester-rke2-svcs`; this copy is scoped to
ci-components issues only.

## What's here

| File | Purpose | Tracked in git? |
|---|---|---|
| `platform-track.sh` | CLI wrapper (open/close/add/remove/list/status) | yes |
| `watcher.sh` | Persistent poller (intended to run as a Monitor task) | yes |
| `active_watch.json` | Current ledger (re-read every 60s by watcher) | yes (seed state) |
| `tracked_items_history.jsonl` | Append-only audit log | no (gitignored) |

## CLI

```
platform-track.sh open-issue   <repo> <iid> [reason]
platform-track.sh open-mr      <repo> <iid> [reason]
platform-track.sh close-issue  <repo> <iid> [--force]
platform-track.sh close-mr     <repo> <iid> [--force]
platform-track.sh add-watch    <issue|mr> <repo> <iid> [reason]
platform-track.sh remove-watch <issue|mr> <repo> <iid>
platform-track.sh list
platform-track.sh status       <repo> <iid>
```

Always uses `~/.config/glab-cli-alice` (platform persona). The watcher
auto-resolves its sibling files from `dirname $0`, so the suite is
relocatable as a unit.

## Concurrence rule (close-issue, no `--force`)

Both must hold:
1. A platform user (`.platform_users[]` in the ledger) AND a
   non-platform user have posted a non-system comment.
2. The most recent comment from each side contains an agreement
   keyword (`ok to close | confirmed | verified | lgtm | all good |
   works | closing | merged | resolved | fixed end-to-end | good
   to go`).
3. The most recent 5 comments contain NO objection keyword (`blocked
   | still failing | still broken | regression | wait | do not close
   | premature | not ready`).

Without all three, `close-issue` refuses and prints what's missing.
`--force` overrides; the override is recorded in the audit log.

## Watcher behavior

1. Poll repos in `.watched_repos_for_new_issues[]`; auto-add new open
   issues to the ledger.
2. Poll each ledger item's state; if closed/merged, auto-remove.
3. Poll each open issue's notes; emit one event per new non-system
   comment, update the ledger.

## DO NOT

- Put `Fixes #N` / `Closes #N` / `Resolves #N` in MR descriptions for
  cross-team issues — GitLab auto-closes them on merge, bypassing the
  concurrence check. Use `Refs #N` instead.
- Use `glab issue close` directly on cross-team issues; use
  `platform-track.sh close-issue` so the rule is enforced.
- Bypass CI gates. See `memory/feedback_never_bypass_gates.md`.
