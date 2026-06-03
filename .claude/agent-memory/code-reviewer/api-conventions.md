---
name: API Conventions
description: Response envelope, error shape, JWT structure, naming
type: project
---

# pguard API conventions

## Response envelope (all REST endpoints)

Success:
```json
{ "data": { ... }, "meta": { "request_id": "..." } }
```

Error:
```json
{ "error": { "code": "VALIDATION_FAILED", "message": "...", "fields": { "phone": "must be 10 digits" } }, "meta": { "request_id": "..." } }
```

Error codes are stable identifiers (`SCREAMING_SNAKE`). HTTP status is the transport layer; clients should also branch on `error.code`.

## JWT shape

```json
{
  "sub": "<user_uuid>",
  "aud": "pguard",
  "iss": "pguard-identity",
  "iat": <unix>,
  "exp": <unix>,
  "jti": "<uuid>",
  "trv": <token_revocation_version>,
  "role": "guard" | "customer" | "admin"
}
```

Service-JWT:
```json
{
  "sub": "<service-name>-service",
  "aud": "pguard-internal",
  "iss": "pguard-platform",
  "iat": ..., "exp": ..., "jti": "..."
}
```

## Pagination

`?limit=N&offset=M` — newest-first. Response includes `meta.total` only when cheap to compute (count(*) on small set).
For large sets use cursor: `?after=<opaque_cursor>&limit=N` → response `meta.next_cursor`.

## Naming

- URL paths: kebab-case (`/guard-requests`, `/cost-summary`)
- Query params: snake_case (`?guard_id=...&limit=20`)
- JSON fields: snake_case
- Enums: lowercase strings (`"pending_acceptance"`, not `"PENDING_ACCEPTANCE"`)

## Versioning

Public: `/v1/{service}/{resource}`. Breaking change → `/v2/{resource}` for that resource only (not whole service).
Sunset header: `Sunset: Wed, 31 Dec 2026 23:59:59 GMT` + `Deprecation: true` for 90 days minimum.
