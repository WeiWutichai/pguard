# 07 — PDPA Compliance Audit (Phase 0.5 · B2)

> Thai **Personal Data Protection Act B.E. 2562 (2019)**. Scope: personal data
> processed by guard-dispatch v1, gaps vs PDPA, and fixes to fold into v2.
> Findings verified against v1 code/migrations (June 2026), not assumed.
>
> ⚠️ **Corrections vs the planning brief:** (a) the brief listed `audit.logs` — the
> real table is `audit.audit_logs`; (b) the brief stated `location_history` already
> has 90-day retention — **it does not** (code comment confirms it is an
> unimplemented TODO, see §7.3); (c) the brief's inventory missed check-in photos,
> session IPs, FCM device tokens, and call logs — added below.

## §7.1 Personal Data Inventory

Verified from `database/migrations/`. Classification: **S** = sensitive/high-risk, **R** = regular.

| Store | Personal data | Class | Current retention | Legal basis (proposed) |
|---|---|---|---|---|
| `auth.users` | phone, password hash, role, approval_status | R | none defined | contract (service provision) |
| `auth.customer_profiles` | full name, phone, email, address, company | R | none | contract |
| `auth.guard_profiles` | name, **gender, DOB**, address, **bank acct (masked)**, emergency contact, **5 doc images** (ID card, security license, training cert, criminal check, driver license) | **S** | none | contract + legal obligation (vetting) |
| `auth.sessions` | **ip_address (INET), device_info** | R | none (until logout/expiry) | legitimate interest (security) |
| `auth.otp_codes` | phone, code | R | **✅ hourly purge of expired** (`auth/main.rs:206`) | contract |
| `booking.guard_requests` | service **address + location** | R | none | contract |
| `booking.payments` | amount, method, status (no PAN stored) | R | none | contract + legal (accounting) |
| `booking.progress_reports` + `progress_report_media` | **hourly check-in photos + reverse-geocoded place names + GPS** | **S** | none | contract (proof of service) |
| `tracking.guard_locations` | **real-time GPS** | **S** | overwritten (current only) | contract |
| `tracking.location_history` | **GPS history** | **S** | ⚠️ **none — TODO, not implemented** (§7.3) | contract |
| `chat.conversations` / `messages` / `attachments` / `read_receipts` | **private message content + uploaded images/video** | **S** | none | contract |
| `calls.call_logs` | caller/callee, timestamps, duration | R | none | contract |
| `notification.fcm_tokens` | **device push token**, device_type | R | none (until token rotates) | consent (notifications) |
| `reviews.guard_reviews` | review text, rating, author | R | none | legitimate interest |
| `audit.audit_logs` | user_id, IP per action | R | none defined | legal obligation |

**Sensitive-data hotspots:** guard documents (ID/criminal check), GPS history,
check-in photos, and private chat content. These drive the highest obligations.

## §7.2 PDPA Rights Coverage

| Right | Current support (verified) | Gap |
|---|---|---|
| §19 Right to access / data export | ❌ no export endpoint (only `GET /me` returns own profile, `auth/handlers.rs:322`) | build `GET /me/data-export` → JSON of all user data across services |
| §20 Right to rectification | ✅ partial — `PUT /me` (`handlers.rs:349`); guard docs & customer profile editable | adequate; document the flow |
| §30 Right to be informed of processing | ❌ no in-app privacy policy / processing notice | privacy policy page + notice on signup |
| §31 Right to withdraw consent | ❌ none (no per-purpose consent flags) | per-purpose consent: marketing push, location sharing |
| §32 Right to data portability | ❌ none | machine-readable export (extends §19) |
| §33 Right to erasure | ❌ no delete-account flow (`/me` has no DELETE) | soft-delete: PII redaction + retain audit minimally |
| §34 Breach notification | ❌ no process | runbook: notify ETDA + affected within 72h |

## §7.3 Retention Policy Gaps

| Store | Current | Recommended |
|---|---|---|
| `tracking.location_history` | ⚠️ **NONE — unbounded.** `tracking/src/service.rs:108-110` explicitly notes "grows unbounded… set up a scheduled job to DELETE rows older than ~90 days" but **no such job exists** | implement 90-day purge (pg_cron or scheduled task); this is the highest-volume sensitive store |
| `tracking.guard_locations` | current-only (upsert) | OK |
| `auth.otp_codes` | ✅ hourly purge of expired | OK |
| `auth.sessions` | until expiry/logout | add max-age purge of stale rows |
| `booking.progress_reports` media (S3 + DB) | none | retain while account active; purge 90 days after account deletion |
| `chat.messages` + `attachments` (S3) | none | retain while account active; purge 90 days after deletion |
| `auth.guard_profiles` doc images (S3) | none | retain while active; purge 90 days after deletion (mind legal-hold for vetting) |
| `audit.audit_logs` | none defined | 2 years, then archive |

**Headline gap:** sensitive GPS history has **no retention enforcement at all** —
the brief assumed it was handled; it is not.

## §7.4 Data Access Audit (PDPA §30)

`audit.audit_logs` exists but records **actions/writes**, not reads. PDPA expects a
trail of *who accessed* personal data. **Gap:** admin `GET`s of customer/guard
profiles, documents, GPS history, and chat are not audited. → add (at least opt-in)
read-audit for admin access to personal data.

## §7.5 Cross-Border Transfer (PDPA §28)

| Service | Provider / location | Concern |
|---|---|---|
| Cloudflare R2 (images, docs, video) | Cloudflare — region depends on bucket config | if outside Thailand, needs adequacy or Standard Contractual Clauses; **document the bucket region** |
| FCM (push) | Google — US | device token + notification payload leaves TH; document mechanism + minimize payload PII |

**Action:** document the storage region for R2 and the FCM transfer basis; put SCCs
in place where required.

## §7.6 Top PDPA Risks (ranked)

| # | Risk | Severity | Fix |
|---|---|---|---|
| 1 | No right-to-erasure (no account deletion) | 🔴 CRITICAL | `DELETE /me` soft-delete + PII redaction |
| 2 | No data-export endpoint | 🔴 CRITICAL | `GET /me/data-export` (cross-service aggregate) |
| 3 | No in-app privacy policy / processing notice | 🔴 CRITICAL | policy page + consent capture on signup |
| 4 | **GPS `location_history` has no retention** (unbounded sensitive data) | 🔴 CRITICAL | implement 90-day purge job (was assumed done — is not) |
| 5 | No breach-notification process | 🟠 HIGH | 72-hour runbook (ETDA + affected users) |
| 6 | No read-access audit for admin viewing personal data | 🟠 HIGH | log admin GETs of profiles/docs/GPS/chat |
| 7 | No cross-border transfer documentation (R2, FCM) | 🟠 HIGH | document regions + SCCs |
| 8 | No consent-withdrawal / per-purpose consent | 🟡 MEDIUM | consent flags (marketing, location) |
| 9 | No retention policy for chat, docs, audit, sessions | 🟡 MEDIUM | retention matrix (§7.3) + enforcement |

## Mapping into v2

- §19/§32/§33 (export, portability, erasure) → **identity + profile services** own a
  `data-export` and `account-deletion` flow; other services expose internal export
  hooks consumed over the API/events.
- §7.4 read-audit → emit `pguard.events.*` access events into the audit pipeline.
- §7.3 retention → scheduled purge jobs per service schema (per-service ownership rule).
- §4 GPS retention → presence service owns the 90-day `location_history` purge.

## Status

✅ §7.1–7.6 complete, verified against v1 code. Numbers/region fields in §7.5 still
need the R2 bucket config + FCM project region from ops to finalize.
