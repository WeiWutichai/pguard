#!/bin/bash
# Pre-tool hook (PreToolUse, matcher "Bash"): block destructive bash commands.
# Claude Code delivers the tool call as JSON on STDIN (NOT argv / env vars); the Bash
# command lives at `.tool_input.command`. Exit 2 = block the call (stderr is shown to Claude).
# See https://code.claude.com/docs/en/hooks.md

INPUT=$(cat)

# Extract the command from the stdin JSON — jq if present, else a python3 fallback so the hook
# still works on a machine without jq. Empty (non-Bash / malformed) → nothing to check → allow.
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
elif command -v python3 >/dev/null 2>&1; then
    COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
else
    COMMAND=""
fi
[[ -z "$COMMAND" ]] && exit 0

# Dangerous patterns — block by default; user can confirm and run themselves
DANGEROUS_PATTERNS=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf \\*"
    "rm -rf \\."
    "rm -fr /"
    "DROP TABLE"
    "DROP SCHEMA"
    "DROP DATABASE"
    "TRUNCATE TABLE"
    "DELETE FROM.*WHERE.*1=1"
    "DELETE FROM.*WHERE.*1 = 1"
    "DELETE FROM.*WHERE.*true"
    "sudo rm"
    "mkfs\\."
    "dd if=.* of=/dev/sd"
    "> /dev/sd"
    ":(){ :|:& };:"      # fork bomb
    "chmod -R 777 /"
    "chown -R.*: /"
    "git push.*--force.*main"
    "git push.*--force.*master"
    "git push.*-f.*main"
    "git push.*-f.*master"
    "git reset --hard HEAD~"
    "git filter-branch"
    "git clean -fdx /"
    "kubectl delete.*--all"
    "docker system prune -a -f"
    "docker volume rm.*--force"
    "terraform destroy.*-auto-approve"
    "psql.*-c.*DROP"
    "redis-cli.*FLUSHALL"
    "redis-cli.*FLUSHDB"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        # Exit 2 blocks the tool call; Claude Code surfaces STDERR (not stdout) as the reason.
        {
            echo "🚫 BLOCKED: Destructive pattern detected: '$pattern'"
            echo "   Command: $COMMAND"
            echo "   If this is intentional, run it yourself outside Claude Code."
        } >&2
        exit 2
    fi
done

# Warn (not block) on patterns worth a second look
WARN_PATTERNS=(
    "git push.*--force"
    "git reset --hard"
    "rm -rf"
    "DROP INDEX"
    "ALTER TABLE.*DROP"
    "REVOKE"
)

for pattern in "${WARN_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$pattern"; then
        echo "⚠️  CAUTION: '$pattern' is reversible-ish but can cause problems."
        echo "   Command: $COMMAND"
        # not exiting — let it proceed
        break
    fi
done

exit 0
