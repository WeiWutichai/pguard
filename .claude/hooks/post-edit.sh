#!/bin/bash
# Post-edit hook: runs auto-format + lint after Claude Code edits files
# Supports: .rs (cargo fmt + clippy + unwrap check), .dart (dart format + analyze),
#           .ts/.tsx (prettier + eslint if configured), .py (ruff format + check)
# Silent on success, verbose on issues. Never blocks (exit 0).

FILE="$1"

# Skip if no file
if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then
    exit 0
fi

# Find nearest project root (folder with Cargo.toml, pubspec.yaml, package.json, or pyproject.toml)
find_project_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]] && [[ -n "$dir" ]]; do
        if [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/pubspec.yaml" ]] || \
           [[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

PROJECT_ROOT=$(find_project_root "$(dirname "$FILE")")
[[ -z "$PROJECT_ROOT" ]] && exit 0

EXT="${FILE##*.}"

case "$EXT" in
    rs)
        echo "🔧 Rust post-edit: $FILE"

        # 1. cargo fmt the project (cheap, reformats touched file too)
        if command -v cargo >/dev/null 2>&1; then
            (cd "$PROJECT_ROOT" && cargo fmt 2>&1 | head -5)
        fi

        # 2. unwrap/expect check in the touched file (request-path concern)
        UNWRAP_COUNT=$(grep -cE "\.unwrap\(\)|\.expect\(" "$FILE" 2>/dev/null || echo 0)
        if [[ "$UNWRAP_COUNT" -gt 0 ]]; then
            echo "⚠️  $UNWRAP_COUNT .unwrap()/.expect() call(s) in $FILE — replace with ? or proper error handling"
            grep -nE "\.unwrap\(\)|\.expect\(" "$FILE" | head -5
        fi

        # 3. clippy on the package — quick, surfaces warnings without -D warnings strictness
        if command -v cargo >/dev/null 2>&1; then
            (cd "$PROJECT_ROOT" && cargo clippy --quiet 2>&1 | grep -E "^(warning|error)" | head -10)
        fi
        ;;

    dart)
        echo "🔧 Dart post-edit: $FILE"

        # 1. dart format
        if command -v dart >/dev/null 2>&1; then
            dart format "$FILE" 2>&1 | head -3
        fi

        # 2. dart analyze — surfaces lint issues
        if command -v dart >/dev/null 2>&1; then
            (cd "$PROJECT_ROOT" && dart analyze --no-fatal-infos --no-fatal-warnings "$FILE" 2>&1 | grep -E "^\s*(info|warning|error)" | head -10)
        fi

        # 3. Provider/setState in new file? warn (Riverpod is the v2 standard)
        if grep -qE "ChangeNotifierProvider|Consumer<|context\.watch<|context\.read<" "$FILE"; then
            if ! grep -qE "@riverpod|Riverpod|ProviderScope" "$FILE"; then
                echo "⚠️  Provider/ChangeNotifier detected — pguard v2 standard is Riverpod 2.x. Use @riverpod."
            fi
        fi
        ;;

    ts|tsx|js|jsx)
        echo "🔧 TS/JS post-edit: $FILE"

        # 1. prettier if configured
        if [[ -f "$PROJECT_ROOT/.prettierrc" ]] || [[ -f "$PROJECT_ROOT/.prettierrc.json" ]] || \
           grep -q "prettier" "$PROJECT_ROOT/package.json" 2>/dev/null; then
            if command -v npx >/dev/null 2>&1; then
                (cd "$PROJECT_ROOT" && npx --no-install prettier --write "$FILE" 2>&1 | head -3)
            fi
        fi

        # 2. eslint if configured
        if [[ -f "$PROJECT_ROOT/.eslintrc.json" ]] || [[ -f "$PROJECT_ROOT/eslint.config.js" ]]; then
            if command -v npx >/dev/null 2>&1; then
                (cd "$PROJECT_ROOT" && npx --no-install eslint "$FILE" 2>&1 | head -10) || true
            fi
        fi

        # 3. localStorage/sessionStorage usage = anti-pattern (pguard uses cookies for web tokens)
        if grep -qE "localStorage\.(set|get)Item|sessionStorage\.(set|get)Item" "$FILE"; then
            if grep -qE "token|jwt|auth" "$FILE"; then
                echo "⚠️  localStorage/sessionStorage with token/auth keywords — pguard uses httpOnly cookies for web tokens."
            fi
        fi
        ;;

    py)
        echo "🔧 Python post-edit: $FILE"
        if command -v ruff >/dev/null 2>&1; then
            ruff format "$FILE" 2>&1 | head -3
            ruff check "$FILE" 2>&1 | head -10
        fi
        ;;

    sql)
        # Light check: SELECT * in non-test SQL is a smell
        if grep -qE "SELECT \*" "$FILE" && [[ "$FILE" != *test* ]]; then
            echo "⚠️  SELECT * in $FILE — explicit column list preferred for production queries"
        fi
        ;;
esac

exit 0
