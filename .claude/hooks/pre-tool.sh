#!/bin/bash
# Pre-tool hook: block destructive bash commands
# Runs before every bash tool invocation
# Exit 2 = blocked

COMMAND="$1"

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
        echo "🚫 BLOCKED: Destructive pattern detected: '$pattern'"
        echo "   Command: $COMMAND"
        echo "   If this is intentional, run it yourself outside Claude Code."
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
