#!/usr/bin/env bash
# watcher.sh — long-running poller that re-reads active_watch.json every
# 60s and emits stdout events for new comments, new issues in watched
# repos, and state changes (close/reopen). Intended to be run as a
# Monitor task so each stdout line becomes a session notification.
#
# Adds and removes are picked up automatically by re-reading the ledger
# each cycle; no restart required when add-watch / remove-watch run.
#
# Closes detected here also auto-prune the ledger (so the ledger always
# reflects open work). Audit appended to tracked_items_history.jsonl.
set -uo pipefail

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="${LEDGER:-${_self_dir}/active_watch.json}"
HISTORY="${HISTORY:-${_self_dir}/tracked_items_history.jsonl}"
GLAB_CONFIG_DIR="${GLAB_CONFIG_DIR:-$HOME/.config/glab-cli-alice}"
export GLAB_CONFIG_DIR
INTERVAL="${POLL_INTERVAL:-60}"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_event() {
  local event="$1"; shift
  jq -nc --arg ts "$(now)" --arg ev "$event" "$@" '
    {ts: $ts, event: $ev} + $ARGS.named
  ' >> "$HISTORY"
}

encode_repo() { echo "$1" | sed 's|/|%2F|g'; }

# Track which iids we've already seen as "new" per repo so we don't emit dupes
declare -A SEEN_NEW_IIDS=()

# Prime SEEN_NEW_IIDS with every CURRENTLY open issue in each watched repo so
# we only emit events for issues opened AFTER the watcher started. Without
# this we'd flood with one NEW ISSUE per existing open issue on first poll.
prime_seen() {
  local watched
  watched="$(jq -r '.watched_repos_for_new_issues[]?' "$LEDGER" 2>/dev/null || true)"
  for repo in $watched; do
    local enc; enc="$(encode_repo "$repo")"
    local open_list
    open_list="$(glab api "projects/${enc}/issues?state=opened&per_page=100" 2>/dev/null || true)"
    [ -z "$open_list" ] && continue
    while IFS= read -r iid; do
      [ -z "$iid" ] && continue
      SEEN_NEW_IIDS["${repo}#${iid}"]=1
    done < <(echo "$open_list" | jq -r '.[].iid' 2>/dev/null)
  done
  echo "[watcher] primed ${#SEEN_NEW_IIDS[@]} existing open issues across $(echo "$watched" | wc -w) watched repos"
}
prime_seen

ledger_remove() {
  local type="$1" repo="$2" iid="$3"
  local tmp; tmp="$(mktemp)"
  jq --arg t "$type" --arg r "$repo" --argjson i "$iid" \
    '.items |= map(select(.type != $t or .repo != $r or .iid != $i))' \
    "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
}

ledger_update_last_note() {
  local type="$1" repo="$2" iid="$3" note_id="$4"
  local tmp; tmp="$(mktemp)"
  jq --arg t "$type" --arg r "$repo" --argjson i "$iid" --argjson nid "$note_id" \
    '(.items[] | select(.type==$t and .repo==$r and .iid==$i)).last_seen_note_id = $nid' \
    "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
}

ledger_add_new() {
  local type="$1" repo="$2" iid="$3" title="$4"
  local last_id="0"
  local new_item; new_item="$(jq -nc \
    --arg t "$type" --arg r "$repo" --argjson i "$iid" --arg title "$title" \
    --arg added "$(now)" --argjson last "$last_id" \
    '{type: $t, repo: $r, iid: $i, title: $title,
      added_at: $added, added_reason: "auto-detected (new)",
      last_seen_note_id: $last,
      other_team_users: []}')"
  local tmp; tmp="$(mktemp)"
  jq --argjson item "$new_item" '.items += [$item]' "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
}

while true; do
  if [ ! -f "$LEDGER" ]; then
    echo "[watcher] ledger missing: $LEDGER"
    sleep "$INTERVAL"
    continue
  fi

  # 1) Detect NEW open issues in watched repos
  watched_repos="$(jq -r '.watched_repos_for_new_issues[]' "$LEDGER" 2>/dev/null || true)"
  for repo in $watched_repos; do
    enc="$(encode_repo "$repo")"
    open_list="$(glab api "projects/${enc}/issues?state=opened&per_page=100" 2>/dev/null)"
    [ -z "$open_list" ] && continue
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      iid="$(echo "$row" | jq -r '.iid')"
      title="$(echo "$row" | jq -r '.title')"
      key="${repo}#${iid}"
      already_in_ledger="$(jq -e --arg r "$repo" --argjson i "$iid" \
        '.items | any(.repo==$r and .iid==$i)' "$LEDGER" 2>/dev/null)"
      if [ "$already_in_ledger" = "true" ]; then continue; fi
      if [ -n "${SEEN_NEW_IIDS[$key]:-}" ]; then continue; fi
      SEEN_NEW_IIDS[$key]=1
      author="$(echo "$row" | jq -r '.author.username')"
      echo "NEW ISSUE ${repo}#${iid} by ${author}: ${title}"
      ledger_add_new issue "$repo" "$iid" "$title"
      log_event "issue_opened_auto" --arg repo "$repo" --argjson iid "$iid" --arg author "$author" --arg title "$title"
    done < <(echo "$open_list" | jq -c '.[]')
  done

  # 2) For each item in ledger: detect new notes and state changes
  while IFS= read -r item; do
    [ -z "$item" ] && continue
    type="$(echo "$item" | jq -r '.type')"
    repo="$(echo "$item" | jq -r '.repo')"
    iid="$(echo "$item" | jq -r '.iid')"
    last_seen="$(echo "$item" | jq -r '.last_seen_note_id // 0')"
    enc="$(encode_repo "$repo")"

    # State (issues + MRs)
    if [ "$type" = "issue" ]; then
      data="$(glab api "projects/${enc}/issues/${iid}" 2>/dev/null)"
    else
      data="$(glab api "projects/${enc}/merge_requests/${iid}" 2>/dev/null)"
    fi
    [ -z "$data" ] && continue
    state="$(echo "$data" | jq -r '.state')"

    if [ "$state" = "closed" ] || [ "$state" = "merged" ]; then
      closer="$(echo "$data" | jq -r '.closed_by.username // .merged_by.username // "n/a"')"
      echo "${type^^} ${repo}#${iid} -> ${state} (by ${closer}) — auto-removing from watch"
      ledger_remove "$type" "$repo" "$iid"
      log_event "${type}_${state}_auto" --arg repo "$repo" --argjson iid "$iid" --arg by "$closer"
      continue
    fi

    # New notes (issues only — MR comments use a different endpoint shape;
    # extend if needed)
    [ "$type" = "issue" ] || continue
    notes="$(glab api "projects/${enc}/issues/${iid}/notes?per_page=100&sort=asc" 2>/dev/null)"
    [ -z "$notes" ] && continue
    new_max="$last_seen"
    while IFS= read -r note; do
      [ -z "$note" ] && continue
      nid="$(echo "$note" | jq -r '.id')"
      if [ "$nid" -le "$last_seen" ]; then continue; fi
      author="$(echo "$note" | jq -r '.author.username')"
      preview="$(echo "$note" | jq -r '.body' | head -c 200 | tr '\n' ' ')"
      echo "${repo}#${iid} note ${nid} by ${author}: ${preview}"
      log_event "comment" --arg repo "$repo" --argjson iid "$iid" --argjson note_id "$nid" --arg author "$author" --arg preview "$preview"
      if [ "$nid" -gt "$new_max" ]; then new_max="$nid"; fi
    done < <(echo "$notes" | jq -c '.[] | select(.system==false)')

    if [ "$new_max" -gt "$last_seen" ]; then
      ledger_update_last_note "$type" "$repo" "$iid" "$new_max"
    fi
  done < <(jq -c '.items[]' "$LEDGER" 2>/dev/null)

  sleep "$INTERVAL"
done
