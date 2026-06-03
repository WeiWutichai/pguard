---
name: v1 Anti-pattern Library
description: Specific patterns from v1 to grep for and block in v2
type: project
---

# v1 anti-pattern detection (grep patterns)

Run these greps on every architecturally significant PR.

## Cross-schema writes

```bash
# In any service except notification, find writes to notification schema
grep -rn "INSERT INTO notification\." services/ --include="*.rs" | grep -v "services/notification/"

# In any service except chat, find writes to chat schema
grep -rn "INSERT INTO chat\." services/ --include="*.rs" | grep -v "services/chat/"

# In any service except messaging, find writes to messaging schema (if consolidated)
grep -rn "INSERT INTO messaging\." services/ --include="*.rs" | grep -v "services/messaging/"
```

If any match → block. Replacement is event emit.

## Direct fire-and-forget state changes

```bash
grep -rn "tokio::spawn.*async move.*INSERT\|tokio::spawn.*async move.*UPDATE" services/ --include="*.rs"
```

Fire-and-forget loses on crash. Must use transactional outbox.

## Domain layer leakage

```bash
# Anything importing I/O in domain/
for f in services/*/src/domain/*.rs; do
  if grep -qE "^use (sqlx|reqwest|axum|s3|aws_sdk)" "$f"; then
    echo "LEAK: $f imports I/O"
  fi
done
```

## Provider/setState in new Flutter features

```bash
grep -rn "ChangeNotifierProvider\|MultiProvider\|Consumer<\|context\.watch<\|context\.read<" apps/mobile/lib/features/ --include="*.dart"
```

In `features/` (new code) → block. In `core/legacy/` during migration → OK.

## Timer.periodic for booking status

```bash
# Find Timer.periodic in screens that involve booking/assignment
grep -rln "Timer\.periodic" apps/mobile/lib/features/ | while read f; do
  if grep -qE "assignment|booking|active_job|tracking" "$f"; then
    echo "POLLING in $f"
  fi
done
```

Use AssignmentSocketService instead.

## .unwrap() in request handler path

```bash
# Skip startup and test
grep -rn "\.unwrap()\|\.expect(" services/*/src/api/ services/*/src/handlers/ --include="*.rs" \
  | grep -vE "^.*#\[cfg\(test\)\]"
```

## SQL injection vector

```bash
grep -rn "format!\(.*SELECT\|format!\(.*INSERT\|format!\(.*UPDATE\|format!\(.*DELETE" services/ --include="*.rs"
```

Should be `query!()` macro or `query()` with bound params, never `format!`.

## Missing OTel spans

```bash
# Handlers without #[tracing::instrument] or .in_current_span() pattern
for f in services/*/src/api/*.rs services/*/src/handlers/*.rs; do
  if grep -q "pub async fn" "$f" && ! grep -q "#\[tracing::instrument\|tracing::span!" "$f"; then
    echo "NO SPAN: $f"
  fi
done
```

Warn — not block.

## LOC per file

```bash
for f in services/*/src/**/*.rs apps/mobile/lib/**/*.dart; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt 800 ]; then
    echo "BIG FILE: $f ($lines LOC)"
  fi
done
```

Warn at 800, escalate at 1500.
