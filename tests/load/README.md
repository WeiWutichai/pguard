<!-- pguard v2 scaffold stub — load tests. See CLAUDE.md "tests/load". -->
# Load tests — k6

New pguard v2 load scripts land here (`tests/load/*.js`).

> **NOTE — do not duplicate the baseline.** The validated v1 performance-baseline k6
> scripts already live in `v1-audit/perf-baseline/scripts/` (with results in
> `v1-audit/perf-baseline/results.md`). Those are the **regression reference** — leave
> them in place. Author *new* pguard-targeted scenarios here, then compare against that
> baseline ("Will this regress?" → CLAUDE.md).

## Scenarios to cover (v2)

- Booking discovery + assignment under concurrent guard load.
- WebSocket fan-out for booking status + presence GPS (replaces v1 REST polling).
- Payment/refund + proration hot paths.
- Gateway rate-limit / JWT validation overhead at the edge.

## Running (wire when k6 is pinned)

```bash
k6 run tests/load/<scenario>.js   # target a dev/staging gateway, never prod
```

Record results and diff against `v1-audit/perf-baseline/results.md` to catch regressions.
