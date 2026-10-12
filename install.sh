#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [--uninstall] [--no-skill] [--help]

Link commands into ${PREFIX:-$HOME/.local/bin} and copy the Claude Code
skill into ${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-app.

  --uninstall  Remove command links and the installed codex-app skill
  --no-skill   Skip skill installation or removal
  --help       Show this help
EOF
}

uninstall=0
skill=1
for arg in "$@"; do
  case "$arg" in
    --uninstall) uninstall=1 ;;
    --no-skill) skill=0 ;;
    --help) usage; exit 0 ;;
    *) printf 'install.sh: unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local/bin}"
skill_dir="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/codex-app"

if [[ "$uninstall" -eq 1 ]]; then
  for command in codex-app-send codex-app-result; do
    link="$prefix/$command"
    if [[ -L "$link" && "$(readlink "$link")" == "$root/bin/$command" ]]; then
      rm "$link"
    fi
  done
  if [[ "$skill" -eq 1 ]]; then rm -rf "$skill_dir"; fi
  echo 'Uninstalled claude-codex-bridge.'
  exit 0
fi

mkdir -p "$prefix"
for command in codex-app-send codex-app-result; do
  link="$prefix/$command"
  if [[ -e "$link" && ! -L "$link" ]]; then
    printf 'install.sh: refusing to overwrite %s\n' "$link" >&2
    exit 1
  fi
  ln -sfn "$root/bin/$command" "$link"
done
if [[ "$skill" -eq 1 ]]; then
  mkdir -p "$skill_dir"
  cp -R "$root/skills/codex-app/." "$skill_dir/"
fi
printf 'Installed commands in %s\n' "$prefix"
case ":$PATH:" in
  *":$prefix:"*) ;;
  *) printf 'Add %s to your PATH to use the commands.\n' "$prefix" ;;
esac
