#!/usr/bin/env bash
# platform-track.sh — ledger-driven issue/MR tracker for the platform side.
#
# Backs the Monitor task that watches /tmp/active_watch.json. The watcher
# re-reads the ledger every 60s, so add/remove takes effect without
# restart.
#
# All glab calls go through the Alice config (~/.config/glab-cli-alice).
# Concurrence rule: an issue is only "OK to close" when BOTH a platform
# user AND a non-platform user have left a non-system comment that
# contains an agreement keyword. close-issue/close-mr enforces this
# unless --force is passed.
set -euo pipefail

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="${LEDGER:-${_self_dir}/active_watch.json}"
HISTORY="${HISTORY:-${_self_dir}/tracked_items_history.jsonl}"
GLAB_CONFIG_DIR="${GLAB_CONFIG_DIR:-$HOME/.config/glab-cli-alice}"
export GLAB_CONFIG_DIR

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_event() {
  local event="$1"; shift
  jq -nc --arg ts "$(now)" --arg ev "$event" "$@" '
    {ts: $ts, event: $ev} + $ARGS.named
  ' >> "$HISTORY"
}

usage() {
  cat <<USAGE
Usage:
  platform-track.sh open-issue   <repo> <iid> [reason]
  platform-track.sh open-mr      <repo> <iid> [reason]
  platform-track.sh close-issue  <repo> <iid> [--force]
  platform-track.sh close-mr     <repo> <iid> [--force]
  platform-track.sh add-watch    <type:issue|mr> <repo> <iid> [reason]
  platform-track.sh remove-watch <type:issue|mr> <repo> <iid>
  platform-track.sh list
  platform-track.sh status       <repo> <iid>     # show concurrence read

Env:
  LEDGER  (default /tmp/active_watch.json)
  HISTORY (default /tmp/tracked_items_history.jsonl)
USAGE
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
encode_repo() {
  echo "$1" | sed 's|/|%2F|g'
}

ledger_has() {
  local type="$1" repo="$2" iid="$3"
  jq -e --arg t "$type" --arg r "$repo" --argjson i "$iid" \
    '.items | any(.type==$t and .repo==$r and .iid==$i)' "$LEDGER" >/dev/null
}

ledger_add() {
  local type="$1" repo="$2" iid="$3" title="${4:-}" reason="${5:-}"
  local platform_users="$(jq -c '.platform_users' "$LEDGER")"
  local last_id="$(latest_note_id "$repo" "$iid" || echo 0)"
  local new_item="$(jq -nc \
    --arg t "$type" --arg r "$repo" --argjson i "$iid" \
    --arg title "$title" --arg added "$(now)" \
    --arg reason "$reason" --argjson last "$last_id" \
    '{type: $t, repo: $r, iid: $i, title: $title,
      added_at: $added, added_reason: $reason,
      last_seen_note_id: $last,
      other_team_users: []}')"
  local tmp="$(mktemp)"
  jq --argjson item "$new_item" '.items += [$item]' "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
  log_event "watch_added" --arg type "$type" --arg repo "$repo" --argjson iid "$iid" --arg reason "$reason"
  echo "[track] +watch ${type} ${repo}#${iid}"
}

ledger_remove() {
  local type="$1" repo="$2" iid="$3"
  local tmp="$(mktemp)"
  jq --arg t "$type" --arg r "$repo" --argjson i "$iid" \
    '.items |= map(select(.type != $t or .repo != $r or .iid != $i))' \
    "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
  log_event "watch_removed" --arg type "$type" --arg repo "$repo" --argjson iid "$iid"
  echo "[track] -watch ${type} ${repo}#${iid}"
}

latest_note_id() {
  local repo="$1" iid="$2"
  glab api "projects/$(encode_repo "$repo")/issues/${iid}/notes?per_page=100" 2>/dev/null \
    | jq -r '[.[] | select(.system==false) | .id] | max // 0'
}

# Concurrence check: returns 0 if both teams agree, 1 otherwise.
# "Agreement" = each side's most recent non-system comment contains
# a positive keyword (ok|confirmed|verified|lgtm|all good|works|closing|merged)
# AND no objection keyword (blocked|wait|still failing|regression|broken)
# in the most recent 5 comments.
check_concurrence() {
  local repo="$1" iid="$2"
  local enc; enc="$(encode_repo "$repo")"
  local notes; notes="$(glab api "projects/${enc}/issues/${iid}/notes?per_page=100&sort=desc" 2>/dev/null)"
  if [ -z "$notes" ] || [ "$notes" = "null" ]; then
    echo "  no notes — cannot validate concurrence"
    return 1
  fi

  local platform_users; platform_users="$(jq -c '.platform_users' "$LEDGER")"

  # Most recent non-system note from a platform user
  local plat_note
  plat_note="$(echo "$notes" | jq -c --argjson p "$platform_users" \
    '[.[] | select(.system==false) | select(.author.username as $a | $p | index($a))] | .[0] // null')"

  # Most recent non-system note from a NON-platform user
  local other_note
  other_note="$(echo "$notes" | jq -c --argjson p "$platform_users" \
    '[.[] | select(.system==false) | select(.author.username as $a | ($p | index($a)) | not)] | .[0] // null')"

  if [ "$plat_note" = "null" ]; then
    echo "  ✗ no platform comment found"
    return 1
  fi
  if [ "$other_note" = "null" ]; then
    echo "  ✗ no other-team comment found"
    return 1
  fi

  local plat_body other_body
  plat_body="$(echo "$plat_note" | jq -r '.body' | tr 'A-Z' 'a-z')"
  other_body="$(echo "$other_note" | jq -r '.body' | tr 'A-Z' 'a-z')"
  local plat_author other_author plat_ts other_ts
  plat_author="$(echo "$plat_note" | jq -r '.author.username')"
  other_author="$(echo "$other_note" | jq -r '.author.username')"
  plat_ts="$(echo "$plat_note" | jq -r '.created_at')"
  other_ts="$(echo "$other_note" | jq -r '.created_at')"

  echo "  most-recent platform: ${plat_author} @ ${plat_ts}"
  echo "    body[0:200]: $(echo "$plat_body" | head -c 200)"
  echo "  most-recent other:    ${other_author} @ ${other_ts}"
  echo "    body[0:200]: $(echo "$other_body" | head -c 200)"

  local agreement_re='(ok to close|confirmed|verified|lgtm|all good|works|closing|merged|resolved|fixed end-to-end|good to go)'
  local objection_re='(blocked|still failing|still broken|regression|wait|do not close|premature|not ready)'

  # Recent objection in either team's last 5 comments?
  local recent_obj
  recent_obj="$(echo "$notes" | jq -r '[.[] | select(.system==false)][:5] | .[].body' | tr 'A-Z' 'a-z' | grep -oE "$objection_re" | head -1 || true)"
  if [ -n "$recent_obj" ]; then
    echo "  ✗ recent objection keyword in last 5 comments: '$recent_obj'"
    return 1
  fi

  local plat_agree other_agree
  plat_agree="$(echo "$plat_body" | grep -oE "$agreement_re" | head -1 || true)"
  other_agree="$(echo "$other_body" | grep -oE "$agreement_re" | head -1 || true)"

  if [ -z "$plat_agree" ]; then
    echo "  ✗ platform comment has no agreement keyword"
    return 1
  fi
  if [ -z "$other_agree" ]; then
    echo "  ✗ other-team comment has no agreement keyword"
    return 1
  fi

  echo "  ✓ concurrence: platform '${plat_agree}' + other '${other_agree}'"
  return 0
}

# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------
cmd_open_issue() {
  local repo="$1" iid="$2" reason="${3:-}"
  local title
  title="$(glab api "projects/$(encode_repo "$repo")/issues/${iid}" 2>/dev/null | jq -r '.title')"
  ledger_add issue "$repo" "$iid" "$title" "$reason"
}

cmd_open_mr() {
  local repo="$1" iid="$2" reason="${3:-}"
  local title
  title="$(glab api "projects/$(encode_repo "$repo")/merge_requests/${iid}" 2>/dev/null | jq -r '.title')"
  ledger_add mr "$repo" "$iid" "$title" "$reason"
}

cmd_close_issue() {
  local repo="$1" iid="$2"; shift 2
  local force=0
  for a in "$@"; do [ "$a" = "--force" ] && force=1; done

  echo "[track] concurrence check for ${repo}#${iid}:"
  if [ "$force" -ne 1 ] && ! check_concurrence "$repo" "$iid"; then
    echo "[track] REFUSING to close — concurrence not satisfied. Re-run with --force to override."
    return 2
  fi

  glab issue close "$iid" --repo "$repo" 2>&1 | tail -2
  ledger_remove issue "$repo" "$iid"
  log_event "issue_closed" --arg repo "$repo" --argjson iid "$iid" --argjson force "$force"
}

cmd_close_mr() {
  local repo="$1" iid="$2"; shift 2
  local force=0
  for a in "$@"; do [ "$a" = "--force" ] && force=1; done

  echo "[track] closing MR ${repo}!${iid}"
  if [ "$force" -ne 1 ]; then
    local state; state="$(glab api "projects/$(encode_repo "$repo")/merge_requests/${iid}" | jq -r '.detailed_merge_status')"
    if [ "$state" != "mergeable" ] && [ "$state" != "ci_must_pass" ]; then
      echo "[track] WARN MR detailed_merge_status=${state}"
    fi
  fi
  glab mr close "$iid" --repo "$repo" 2>&1 | tail -2
  ledger_remove mr "$repo" "$iid"
  log_event "mr_closed" --arg repo "$repo" --argjson iid "$iid" --argjson force "$force"
}

cmd_add_watch() {
  local type="$1" repo="$2" iid="$3" reason="${4:-manual add}"
  if ledger_has "$type" "$repo" "$iid"; then
    echo "[track] already watching ${type} ${repo}#${iid}"
    return 0
  fi
  case "$type" in
    issue) cmd_open_issue "$repo" "$iid" "$reason" ;;
    mr)    cmd_open_mr    "$repo" "$iid" "$reason" ;;
    *)     echo "type must be issue|mr"; return 1 ;;
  esac
}

cmd_remove_watch() {
  local type="$1" repo="$2" iid="$3"
  ledger_remove "$type" "$repo" "$iid"
}

cmd_list() {
  jq -r '.items[] | "  \(.type)  \(.repo)#\(.iid)  added=\(.added_at)  last_note=\(.last_seen_note_id)  \(.title // "")"' "$LEDGER"
}

cmd_status() {
  local repo="$1" iid="$2"
  echo "[track] ${repo}#${iid}"
  local enc; enc="$(encode_repo "$repo")"
  local data; data="$(glab api "projects/${enc}/issues/${iid}" 2>/dev/null)"
  echo "  state: $(echo "$data" | jq -r '.state')"
  echo "  title: $(echo "$data" | jq -r '.title')"
  check_concurrence "$repo" "$iid" || true
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
[ $# -eq 0 ] && { usage; exit 1; }
sub="$1"; shift
case "$sub" in
  open-issue)    cmd_open_issue    "$@" ;;
  open-mr)       cmd_open_mr       "$@" ;;
  close-issue)   cmd_close_issue   "$@" ;;
  close-mr)      cmd_close_mr      "$@" ;;
  add-watch)     cmd_add_watch     "$@" ;;
  remove-watch)  cmd_remove_watch  "$@" ;;
  list)          cmd_list          "$@" ;;
  status)        cmd_status        "$@" ;;
  -h|--help)     usage ;;
  *)             usage; exit 1 ;;
esac
