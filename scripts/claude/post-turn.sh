#!/bin/sh
# Claude Code Stop hook.
# After a turn that changed the working tree:
#   1. make test  — run the unit tests
#   2. make dev   — build the app and launch it
#   3. show what changed, so a commit message can be proposed for approval
# It never stages and never commits. A test or build failure stops the chain
# and reports what broke.

set -u

input=$(cat 2>/dev/null || true)

# Don't re-enter when Claude is already continuing from a prior Stop hook.
case "$input" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

# Nothing changed -> stay silent (keeps plain Q&A turns fast).
[ -n "$(git status --porcelain)" ] || exit 0

log=$(mktemp)
trap 'rm -f "$log"' EXIT

emit() {
  # $1 = message body -> Claude Code shows it to the user, hides raw stdout.
  printf '%s' "$1" | jq -Rs '{systemMessage: ., suppressOutput: true}'
  exit 0
}

if ! make test >"$log" 2>&1; then
  emit "$(printf 'Stop hook: tests FAILED - skipped make dev.\n\n%s' "$(tail -n 25 "$log")")"
fi

# Don't relaunch the app while a real sync is running (make open leaves it be,
# but skip the rebuild entirely and say so).
sync_lock="$HOME/Library/Application Support/Strawberry/sync-in-progress.lock"
if [ -f "$sync_lock" ] && pgrep -x Strawberry >/dev/null 2>&1; then
  emit "$(printf 'Stop hook: tests passed. Skipped make dev - a sync is in progress (%s).\n\n%s\n\n%s' \
    "$(cat "$sync_lock")" \
    "$(git -c color.ui=never status --short)" \
    "$(git -c color.ui=never diff --stat HEAD)")"
fi

if ! make dev >>"$log" 2>&1; then
  emit "$(printf 'Stop hook: tests passed but make dev FAILED.\n\n%s' "$(tail -n 25 "$log")")"
fi

emit "$(printf 'Stop hook: tests passed - app built & launched. Nothing staged or committed - propose a commit message for approval.\n\n%s\n\n%s' \
  "$(git -c color.ui=never status --short)" \
  "$(git -c color.ui=never diff --stat HEAD)")"
