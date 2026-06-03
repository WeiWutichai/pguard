---
name: Test Infrastructure
description: docker-compose.test.yml, hermetic patterns, rate-limit handling
type: project
---

# Test infrastructure (pguard v2)

## docker-compose.test.yml

Separate stack for tests. Same services as dev but:
- Different DB name (`pguard_test`)
- Different Redis (different port mapping or namespace)
- No volumes (ephemeral)
- Faster startup (skip migrations on healthcheck wait)

`./tooling/scripts/test-up.sh` brings it up; CI uses it.

## Hermetic per-test

- Each test starts with truncate of relevant tables (use `tests/common/fixtures.rs`)
- Phone/email/UUIDs unique per test (suffix with test name + counter)
- No shared fixtures across tests

## Rate-limit handling

nginx rate limits apply in test too (matches prod) — use `send_retrying()`:

```rust
async fn send_retrying<F, Fut, R>(f: F) -> Result<R, anyhow::Error>
where F: Fn() -> Fut, Fut: Future<Output = Result<R, anyhow::Error>>
{
    let mut delay = Duration::from_millis(200);
    for _ in 0..5 {
        match f().await {
            Ok(r) => return Ok(r),
            Err(e) if e.is_rate_limited() => tokio::time::sleep(delay).await,
            Err(e) => return Err(e),
        }
        delay *= 2;
    }
    f().await
}
```

## CI split (per v2-audit/04-tests.md)

```yaml
jobs:
  unit:                              # fast, no Docker
    runs-on: ubuntu-latest
    steps:
      - run: cargo test --workspace --lib
      - run: cargo test --workspace --doc

  integration:                       # slower, with Docker
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:16, ports: [5432] }
      redis:    { image: redis:7, ports: [6379] }
      nats:     { image: nats:2.10, ports: [4222] }
      minio:    { image: minio/minio, ports: [9000] }
    steps:
      - run: cargo test --workspace --tests -- --test-threads=1

  flutter:                           # NEW for v2 (v1 didn't run flutter test)
    runs-on: ubuntu-latest
    steps:
      - uses: subosito/flutter-action@v2
      - run: cd apps/mobile && flutter test
      - run: cd apps/mobile && flutter test --coverage
      - uses: codecov/codecov-action@v4

  contract:                          # Pact provider/consumer verify
    runs-on: ubuntu-latest
    steps: ...

  load-regression:                   # k6 vs baseline
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - run: k6 run tests/load/scripts/*.js --out json=results.json
      - run: ./tooling/scripts/compare-baseline.sh results.json
        # fails if p99 regresses > +20% vs baseline
```

## Coverage gates

- Domain layer: 90% line coverage minimum
- API layer: 70% (mostly happy + error paths)
- Service overall: 60%
- Money/safety modules: 95% (proration, refund, GPS validate, PIN, JWT)

## Pact contract testing

- Producer (service) writes pacts to broker
- Consumer (mobile/web from generated clients) verifies on CI
- Breaking change → producer pact fails → bump endpoint version → regenerate clients
