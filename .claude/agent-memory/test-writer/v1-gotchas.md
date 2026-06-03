---
name: v1 Test Gotchas
description: Patterns from v1 that caused flaky tests or missed coverage — don't repeat
type: project
---

# v1 test gotchas

## Don't carry over

### Mock DB at backend
v1 didn't mock — every test hit live Postgres. Same for v2 BUT split unit (domain, no DB) from integration (real DB).
Domain functions in `domain/` are pure → unit tests don't need Docker.

### Tests sharing data
v1 integration tests created records with UUID suffix but never truncated → data accumulated. Eventually some tests assumed empty table and broke.
v2: per-test truncate via shared `setup()` helper.

### Tests requiring rate-limit retry
v1 nginx 5r/s auth limit caused test flakes. The `send_retrying()` helper exists — use it for any test that hits `/auth/*`.

### `#[ignore]` on OTP happy path
v1 ignored OTP happy-path tests because they need to capture SMS. v2 should:
- Use a test SMS provider that writes to in-memory queue
- Tests read OTP from that queue
- No `#[ignore]` for happy paths

### Timing-flaky OTP constant-time test
v1 had `#[ignore]` on OTP constant-time test because of timing variance. v2 should use statistical test (run many comparisons, measure variance is below threshold) rather than rely on absolute timing.

### Flutter tests not in CI
v1 ran `cargo test` but not `flutter test`. v2 CI must include both.

### No coverage tracking
v1 had no coverage gate. v2 has gates per layer (see test-infrastructure.md).
