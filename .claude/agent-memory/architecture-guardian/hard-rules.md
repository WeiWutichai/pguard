---
name: Hard Rules
description: 10 architectural rules that block merge on violation
type: project
---

# Hard rules (block merge)

| # | Rule | Detection |
|---|---|---|
| R1 | No cross-schema direct writes | grep `INSERT INTO <other_schema>` in service src |
| R2 | Domain layer purity (no I/O imports) | grep imports in `domain/` for sqlx/reqwest/axum/tokio |
| R3 | Service ≤ 4 domains | count distinct primary-write schema tables |
| R4 | OpenAPI ↔ handler parity | diff `contracts/openapi/<svc>.yaml` operations vs handler operationIds |
| R5 | Service-JWT on `/internal/*` | grep router for `internal` routes, check middleware |
| R6 | Event envelope discipline | grep `nats_client.publish` calls for envelope fields |
| R7 | Riverpod in Flutter (no Provider regress) | grep `ChangeNotifierProvider\|Consumer<` in `apps/mobile/lib/features/` |
| R8 | No polling for assignment/booking status | grep `Timer.periodic` in `features/` and inspect target |
| R9 | Per-service schema ownership | grep `REFERENCES <other_schema>\.` in new migrations |
| R10 | API versioning policy | review OpenAPI for breaking change without version bump |

## Soft rules (warn)

- S1: file LOC > 800 → warn; service src/ total > 6000 LOC → split candidate
- S2: new domain function without unit test
- S3: new handler without OTel span
- S4: scalar subquery per row pattern → suggest CTE/LATERAL
