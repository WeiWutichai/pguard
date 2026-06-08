# Phase 5 / C5.2 — PDPA data-export (§19 access + §32 portability) — work spec

> For Claude Code. The deferred PDPA piece. Branch off the freshly-merged `main`.
> `identity` aggregates a user's data from every owning service over service-JWT into one
> machine-readable JSON. Closes 07-pdpa.md §7.2 §19/§32. Don't merge; don't touch `../guard-dispatch/`.

## Shape

```
GET /v1/me/data-export  (authed user)
  identity (aggregator, adds reqwest)
    └─ fan out, concurrently, over service-JWT:
         profile  GET /internal/users/{id}/export   → profiles + doc references (signed URLs, not bytes)
         booking  GET /internal/users/{id}/export   → the user's bookings/assignments
         payment  GET /internal/users/{id}/export   → the user's payments/refunds/receipts
         rating   GET /internal/users/{id}/export   → reviews authored by the user
    └─ merge into one envelope:
       { user: {...identity fields...}, profile:{...}, bookings:[...], payments:[...], reviews:[...],
         _meta: { generated_at, sections: { profile:"ok", booking:"ok", payment:"ok", rating:"ok" } } }
```

## Rules

- **Own data only.** identity passes the authenticated `user_id`; every `/internal/.../export`
  is `ServiceCaller`-gated (service-JWT) AND scoped to that exact user_id — never accept a
  client-supplied id, never return another user's rows.
- **Best-effort, transparent.** If a downstream service is unavailable, return the rest with
  that section marked `"error"`/`"degraded"` in `_meta.sections` (don't fail the whole export);
  per PDPA the user should still get what's retrievable. Log the failure.
- **Documents:** return metadata + short-lived signed URLs for the user's own files (guard docs,
  chat attachments later) — not raw bytes inline.
- **Machine-readable** (§32 portability): stable JSON, documented in `contracts/openapi/identity.yaml`.
- Per-service schema ownership: each service exports only its own schema; identity owns no business data, just orchestration.
- No `.unwrap()` in the request path; OTel span across the fan-out (the C5.1 trace context already propagates).
- **Not in scope yet** (note as follow-ups): `chat` (service is still a stub) and `presence`/GPS
  `location_history` — add their `/internal/.../export` sections when/if those land.

## Definition of Done

- `cargo clippy --all-targets -D warnings` ✅ · `cargo test --workspace` ✅
- Unit: aggregation/merge shape; per-section partial-failure handling (one downstream down → degraded, others present).
- Authz: each `/internal/.../export` rejects missing/invalid service-JWT, and rejects a mismatched user_id (no cross-user leak).
- Integration (DB + service-JWT): seed a user with profile + bookings + payments + reviews → `GET /v1/me/data-export` returns all four sections populated; kill one service → that section `error`, others still returned.
- Wire `/v1/me/data-export` at the gateway (authed, Api tier).
- Update `PROGRESS.md` (tick the §19/§32 PDPA item + Completed-log row) · run the 3 review agents, fix findings · own PR off main · don't merge.

## Reference (read-only)

- `v1-audit/07-pdpa.md` §7.2 (§19 access, §32 portability — both ❌ in v1) + §7.1 data inventory (what each service holds).
- v2 patterns to reuse: identity's existing service-JWT mint + the discovery fan-out in `services/booking/src/discovery_client.rs` (concurrent, best-effort, order-preserving) — same shape as this aggregator.
- `contracts/openapi/*.yaml` for each service's existing schemas.
