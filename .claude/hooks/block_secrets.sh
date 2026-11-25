#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher: Bash). Blocks `git commit` / `git push` when the
# staged changes contain signing keys or secrets for the IQ2020 project.
# Exit 2 = block; the stderr message is shown to Claude. Exit 0 = allow.
set -euo pipefail

input=$(cat)
field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1" <<<"$input"; }
cmd=$(field 'd.get("tool_input", {}).get("command", "")')
cwd=$(field 'd.get("cwd", ".")')

# Only care about commits and pushes.
echo "$cmd" | grep -qE '\bgit\b.*\b(commit|push)\b' || exit 0
cd "$cwd" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

problems=()

# 1. Files that must never be committed.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *key.properties|*.jks|*.keystore|*.p12|*.p8|*.mobileprovision|*secrets.yaml)
      problems+=("staged secret file: $f") ;;
  esac
done < <(git diff --cached --name-only)

# 2. Secret-looking content in added lines (skip !secret references and known test vectors).
added=$(git diff --cached -U0 | grep -E '^\+[^+]' || true)
if echo "$added" | grep -vE 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=' \
     | grep -qE '[A-Za-z0-9+/]{43}='; then
  problems+=("44-char base64 value (looks like an ESPHome API key)")
fi
if echo "$added" | grep -qE '(storePassword|keyPassword)=[^[:space:]]+'; then
  problems+=("Android keystore password")
fi
if echo "$added" | grep -E '^\+[[:space:]]*(password|key):[[:space:]]*[^[:space:]]' \
     | grep -vqE '!secret|<|\$\{|YOUR_|REPLACE'; then
  problems+=("inline ESPHome key/password (use !secret)")
fi

if [ ${#problems[@]} -gt 0 ]; then
  {
    echo "secretguard blocked this git command. Staged changes contain:"
    printf '  - %s\n' "${problems[@]}"
    echo "Unstage them (git restore --staged <file>) or replace values with !secret references."
  } >&2
  exit 2
fi
exit 0
