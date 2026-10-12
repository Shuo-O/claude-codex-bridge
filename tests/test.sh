#!/usr/bin/env bash
# No test framework needed; the commands themselves require python3.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export PREFIX="$TMP/install bin"
export CLAUDE_SKILLS_DIR="$TMP/skills"
export CODEX_RESULT_POLL_INTERVAL=1
export CODEX_TEST_FORBIDDEN="$TMP/forbidden"
mkdir -p "$HOME"

# Fail closed if a regression ever reaches a desktop side effect.
open() { printf 'open\n' >> "$CODEX_TEST_FORBIDDEN"; return 99; }
osascript() { printf 'osascript\n' >> "$CODEX_TEST_FORBIDDEN"; return 99; }
export -f open osascript

passed=0
failed=0
check() {
  local name="$1"
  shift
  if "$@"; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$name" >&2
    failed=$((failed + 1))
  fi
}
run() {
  rc=0
  output=$("$@" 2>"$TMP/stderr") || rc=$?
  error=$(<"$TMP/stderr")
}
send_check() {
  local expected="$1" pattern="$2"
  shift 2
  run bash "$ROOT/bin/codex-app-send" "$@"
  if [[ "$error" == *'macOS only'* ]]; then
    [[ "$rc" -eq 1 ]]
  else
    [[ "$rc" -eq "$expected" && "$output$error" == *"$pattern"* ]]
  fi
}

cat > "$TMP/done.jsonl" <<'EOF'
{"type":"event_msg","payload":{"type":"task_started"}}
{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Done.\nTests passed."}}
EOF
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_started"}}' > "$TMP/running.jsonl"
cat "$TMP/done.jsonl" "$TMP/running.jsonl" > "$TMP/new-turn.jsonl"
cat "$TMP/new-turn.jsonl" > "$TMP/multi.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Second result."}}' >> "$TMP/multi.jsonl"

run bash "$ROOT/bin/codex-app-result" "$TMP/done.jsonl"
check 'completed turn exits 0' test "$rc" -eq 0
check 'completed turn prints its message' test "$output" = $'Done.\nTests passed.'
run bash "$ROOT/bin/codex-app-result" "$TMP/running.jsonl"
check 'running turn exits 2' test "$rc" -eq 2
check 'running turn has no final output' test -z "$output"
run bash "$ROOT/bin/codex-app-result" "$TMP/multi.jsonl"
check 'multiple turns exit 0' test "$rc" -eq 0
check 'multiple turns return the latest result' test "$output" = 'Second result.'
run bash "$ROOT/bin/codex-app-result" "$TMP/new-turn.jsonl"
check 'new running turn exits 2' test "$rc" -eq 2
check 'new running turn does not return stale result' test -z "$output"
run bash "$ROOT/bin/codex-app-result" "$TMP/missing.jsonl"
check 'missing rollout exits 1' test "$rc" -eq 1
start=$SECONDS
run bash "$ROOT/bin/codex-app-result" --wait 1 "$TMP/running.jsonl"
check 'wait timeout exits 2' test "$rc" -eq 2
check 'wait actually polls before timing out' test "$((SECONDS - start))" -ge 1

check 'send help is safe' send_check 0 'Usage:' --help
check 'send version is safe' send_check 0 'codex-app-send' --version
check 'send rejects unknown option' send_check 1 'unknown option' --unknown
check 'send rejects zero arguments' send_check 1 'Usage:'
check 'send rejects one argument' send_check 1 'Usage:' "$TMP"
check 'send rejects extra arguments' send_check 1 'Usage:' "$TMP" prompt extra

run bash "$ROOT/install.sh" --help
check 'installer help exits 0' test "$rc" -eq 0
check 'installer help makes no changes' test ! -e "$PREFIX"
run bash "$ROOT/install.sh" --unknown
check 'installer rejects unknown option' test "$rc" -eq 1
run bash "$ROOT/install.sh"
check 'install exits 0' test "$rc" -eq 0
check 'send symlink points to checkout' test "$(readlink "$PREFIX/codex-app-send" || true)" = "$ROOT/bin/codex-app-send"
check 'result symlink points to checkout' test "$(readlink "$PREFIX/codex-app-result" || true)" = "$ROOT/bin/codex-app-result"
check 'skill is copied unchanged' cmp -s "$ROOT/skills/codex-app/SKILL.md" "$CLAUDE_SKILLS_DIR/codex-app/SKILL.md"
check 'missing PATH entry is mentioned' test "${output#*PATH}" != "$output"
run bash "$ROOT/install.sh"
check 'reinstall exits 0' test "$rc" -eq 0
check 'reinstall keeps skill layout' test ! -e "$CLAUDE_SKILLS_DIR/codex-app/codex-app"
run env PATH="$PREFIX:$PATH" bash "$ROOT/install.sh"
check 'install with PATH configured exits 0' test "$rc" -eq 0
check 'configured PATH needs no reminder' test "${output#*PATH}" = "$output"
run "$PREFIX/codex-app-result" "$TMP/done.jsonl"
check 'installed result command works' test "$rc:$output" = $'0:Done.\nTests passed.'
run bash "$ROOT/install.sh" --uninstall --no-skill
check 'commands-only uninstall exits 0' test "$rc" -eq 0
check 'commands-only uninstall preserves skill' test -f "$CLAUDE_SKILLS_DIR/codex-app/SKILL.md"
run bash "$ROOT/install.sh" --uninstall
check 'uninstall exits 0' test "$rc" -eq 0
check 'uninstall removes send symlink' test ! -L "$PREFIX/codex-app-send"
check 'uninstall removes result symlink' test ! -L "$PREFIX/codex-app-result"
check 'uninstall removes skill' test ! -e "$CLAUDE_SKILLS_DIR/codex-app"
run bash "$ROOT/install.sh" --uninstall
check 'repeated uninstall exits 0' test "$rc" -eq 0
run bash "$ROOT/install.sh" --no-skill
check 'commands-only install exits 0' test "$rc" -eq 0
check 'commands-only install skips skill' test ! -e "$CLAUDE_SKILLS_DIR/codex-app"
run bash "$ROOT/install.sh" --uninstall --no-skill
check 'commands-only cleanup exits 0' test "$rc" -eq 0
printf 'existing command\n' > "$PREFIX/codex-app-send"
run bash "$ROOT/install.sh" --no-skill
check 'install refuses to replace a regular command file' test "$rc" -eq 1
check 'existing command file is preserved' test "$(<"$PREFIX/codex-app-send")" = 'existing command'
run bash "$ROOT/install.sh" --uninstall --no-skill
check 'uninstall preserves unrelated command files' test -f "$PREFIX/codex-app-send"
unset PREFIX CLAUDE_SKILLS_DIR
run bash "$ROOT/install.sh"
check 'default install exits 0' test "$rc" -eq 0
check 'default command location' test -L "$HOME/.local/bin/codex-app-send"
check 'default skill location' test -f "$HOME/.claude/skills/codex-app/SKILL.md"
run bash "$ROOT/install.sh" --uninstall
check 'default uninstall exits 0' test "$rc" -eq 0
check 'no desktop commands were reached' test ! -e "$CODEX_TEST_FORBIDDEN"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
