# Audit Revisions + Phase 0.5 Brief

> **For Claude Code CLI** — paste this after `pguard-brief.md` Phase 1 completes. This phase has two parts: (A) revise the existing 7 audit files based on user critique, then (B) execute Phase 0.5 (performance baseline + PDPA compliance audit). Gate on user review before proceeding to Phase 0.

---

## Context

User reviewed all 7 files in `v1-audit/` and raised 7 specific issues + corrected one assumption. Apply these changes carefully — preserve the audit's overall structure and the strong code-grounded findings; only revise the specific points called out.

**Correct one factual assumption first:**
The audit assumes "ระบบ production มี user จริง" (see `05-recommendations.md` line 9 and `06-migration-plan.md` heading). **There are NO production users — only dev/staging.** This relaxes several constraints. Cascade this fact through the revisions.

---

## Part A — Revise Existing Audit Files (7 changes)

Use `Edit` tool, not full rewrites. Preserve all citations, tables, and rankings — only change the specific points below.

### A1 — `05-recommendations.md` §5.1 Guiding Principles

**Current line 9:** *"ระบบ production มี user จริง. ใช้ strangler-fig: เพิ่ม/แทนทีละส่วน, ของเก่ายังรันคู่จนกว่าใหม่จะ proven"*

**Change to:** acknowledge dev/staging-only state. Strangler-fig is still useful as a discipline (prevents big-bang risk) but the dual-write/parallel-run overhead can be relaxed where it adds cost without value. Suggested wording:

> "ระบบยังไม่มี production users — เป็น dev/staging เท่านั้น. ใช้ strangler-fig **เป็นวินัย** (ป้องกัน big-bang risk + บังคับให้คิด rollback) **ไม่ใช่ข้อจำกัด user-availability**. แต่ละ phase ต้อง deploy + rollback ได้, แต่ dual-write / parallel-run / fallback **ทำเฉพาะที่ลด risk จริง** — ตัด overhead ที่ไม่จำเป็นได้ (เช่น Phase 1 ไม่ต้อง dual-write นาน, Phase 2 ไม่ต้องคง poll ตลอด rollout, Phase 3 ไม่ต้อง feature-flag traffic routing)"

### A2 — `03-security.md` §3.6 row #2 PIN brute-force math

**Current text:** *"brute force ~55 ชม.จาก distributed IP"*

**Problem:** Math assumes single IP. With distributed 50 IPs × 5r/s = 250 req/s, brute force = 1,000,000 ÷ 250 = ~67 minutes, not 55 hours.

**Change to:** *"brute force ~55 ชม. **single IP** / **~1 ชม. distributed 50 IPs**"* — escalates severity from CRITICAL-bound to clear CRITICAL urgency.

Also update §3.2 PIN row (line ~38) with the same correction. The severity ranking in §3.6 already says CRITICAL — keep it, but make the math justify it more clearly.

### A3 — `05-recommendations.md` §5.2 Per-Service framing

**Problem:** Column "คำตัดสิน" labels tracking/notification/chat/shared as *"Port ตรง"* but the "งานหลัก" column lists meaningful work (test suite from 0 funcs, ingress endpoints, service-JWT, N+1 rewrite, indexes). The "port ตรง" label undersells the actual effort and creates planning risk.

**Change column "คำตัดสิน":**

| Service | New label |
|---|---|
| tracking | 🟢 **Port + Reinforced** |
| notification | 🟢 **Port + Reinforced** |
| chat | 🟡 **Port + Refactor (N+1)** |
| shared | 🟢 **Port + Extend** |
| auth | 🟠 **Module split** (no change) |
| booking | 🔴 **Service split** (no change) |
| web admin | 🟢 **Port + Light hardening** (CSRF, map tiles) |
| Flutter | 🟠 **Refactor in-place** (no change) |

Add a one-line clarification under §5.1 principle #2: *"'Port' ในที่นี้หมายถึง 'reuse architecture + ขยายการรับประกัน' — ไม่ใช่ copy-paste. ทุก service ที่ port ต้องเพิ่ม test ครอบ critical path + ingress patterns ใหม่"*

### A4 — `06-migration-plan.md` Phase 3 order

**Current order:** payment → call → rating → assignment

**Problem:** payment is coupled to assignment via `cost_summary` which reads `started_at` + `booked_hours` from `booking.assignments`. Call signaling is more isolated (own state machine, only writes to `booking.calls` + `chat.messages` BUG-038 which Phase 1 already cleans up).

**Change to:** **call → payment → rating → assignment**

Rationale to add to Phase 3 description:
- **call-svc first** — most isolated (own DB tables, own state machine, no FK to assignment beyond `request_id`). After Phase 1 cleans up the `chat.messages` write, call-svc has zero cross-write. Lowest blast radius.
- **payment-svc second** — has proration test from Phase 0 as safety net. Reads `started_at` + `booked_hours` from assignment → during split, expose those as read-only API from assignment-svc.
- **rating-svc third** — owns `reviews.guard_reviews` schema already. Simple split.
- **assignment-svc last** — keeps the rest. By this point everything else is gone.

### A5 — `05-recommendations.md` §5.4 — Add API Versioning row

Insert this row before "**Inter-service comms**":

| ด้าน | ปัจจุบัน | เสนอ v2 | เหตุผล |
|---|---|---|---|
| **API versioning** | ไม่มี (ทุก endpoint = current) | **`/v1/` prefix ทุก service** + breaking change → `/v2/` per resource (ไม่ทั้ง service) | mobile/web จะแก้ทีละ endpoint ที่เปลี่ยน, ไม่ต้อง coordinate big-bang. gateway route version → service implementation. Deprecate /v1/ ตาม sunset date |

Add a short paragraph after the table:

> **Versioning policy:** API gateway expose `/v{N}/{service}/...`. แต่ละ service version per-resource ใน OpenAPI spec. Breaking change ใน 1 endpoint = bump เฉพาะ endpoint นั้น (ไม่ใช่ทั้ง service). Sunset header (`Sunset: <date>`, `Deprecation: true`) ให้ client transition. Mobile app force-upgrade ถ้า endpoint version ที่ใช้ถูก sunset ไปแล้ว.

### A6 — `06-migration-plan.md` Phase 3 — Schema separation roadmap

**Current text:** *"shared DB ช่วงเปลี่ยน (schema เดิม) → แยก schema ownership ชัดเจน"* — too vague.

**Add explicit 3-step roadmap to Phase 3:**

**Step 3.1 — Schema-per-service in shared DB** (Phase 3 start)
- Each new service owns its schema strictly. `assignment-svc` writes `booking_assignments` schema only. `payment-svc` writes `booking_payments` only. etc.
- Foreign keys across schemas stay temporarily but flagged as "boundary" — no new cross-schema FK allowed.
- Reads across schemas allowed via direct SQL during transition (with read-only role).

**Step 3.2 — Replace cross-schema reads with API calls** (Phase 3 mid)
- assignment-svc exposes `GET /internal/assignments/{id}` for payment-svc to read `started_at`/`booked_hours`.
- Service-JWT auth on these (uses pattern from Phase 1).
- Add caching where appropriate.

**Step 3.3 — DB-per-service** (Phase 5, after stabilization)
- Each service gets its own Postgres database.
- Foreign keys across services removed entirely.
- Eventual consistency tolerated where business allows; transactional outbox for must-be-consistent.

### A7 — `00-overview.md` and `05-recommendations.md` — Add operational gaps row

Audit covers code/architecture but not operational maturity. Add §5.7 "Operational Maturity Gaps" with this table:

| ด้าน | สถานะปัจจุบัน | gap | เสนอ v2 |
|---|---|---|---|
| Backup/restore | manual postgres dump (ตรวจ) | ไม่มี RPO/RTO defined, ไม่มี restore drill | RPO ≤ 1 ชม., RTO ≤ 4 ชม., monthly restore drill |
| Disaster recovery | single-region | ไม่มี | secondary region replica (Phase 5) |
| On-call runbook | ไม่มี | DB ล่ม / Redis ล่ม / nginx ล่ม = ad-hoc | runbook ต่อ component, escalation matrix |
| SLO definition | ไม่มี | ไม่รู้ว่า "ดี" คือเท่าไหร่ | p99 latency + availability per critical path, error budget |
| Monitoring/alerting | logging อย่างเดียว | ไม่มี alert routing | Prometheus + Alertmanager → Slack/PagerDuty |
| Secret rotation | ไม่มี policy | rotate manually เมื่อจำเป็น | quarterly rotation, Vault for prod |
| Cost monitoring | ไม่มี | infra cost ไม่ tracked | monthly cost report per service |

Add to §00-overview.md after section "ระดับความเสี่ยง migration": one-line pointer to §5.7.

### A8 — `06-migration-plan.md` — Add Phase 0.5

Insert between Phase 0 and Phase 1:

```
Phase 0.5  Baseline & Compliance ── perf baseline + PDPA gap audit (no code change)
```

Brief description:
- **Performance baseline (k6):** GPS WS frames/sec, booking create p99, list_conversations p99 at 100 conv/user, available-guards p99 at 50 km radius, payment create p99. Record current numbers — they become the "must not regress" gate for every phase.
- **PDPA compliance audit:** data retention, right-to-erasure, data export, audit-of-data-access (PDPA §30), data subject rights workflows.
- **Cost baseline:** current infra cost per service.
- **Exit criteria:** baseline numbers documented, PDPA gap list with severity, cost report.
- **Rollback:** none — read-only.

Move Phase 1-5 numbering — they stay the same names but shift one slot if you renumber, or keep "Phase 0.5" as half-phase to avoid renumber. **Keep half-phase numbering** to preserve cross-references in other docs.

### A9 — Update `00-overview.md` Migration Risk table

Now that Phase 0.5 exists, add a row before tracking:

| Service / Layer | กลยุทธ์ v2 | ความเสี่ยง |
|---|---|---|
| (Phase 0.5) Baseline + PDPA | Read-only audit | 🟢 ต่ำ |

---

## Part B — Phase 0.5 Execution

After revisions are reviewed and accepted by user, execute Phase 0.5.

### B1 — Performance baseline (k6)

Create `/v1-audit/perf-baseline/`:

**File: `perf-baseline/README.md`** — explain methodology, environment used (local docker compose vs staging), date captured.

**Scripts to write (`perf-baseline/scripts/*.js`):**

1. **`gps-websocket.js`** — open N concurrent WS, push 1 GPS update/sec/connection. Vary N from 10 → 100 → 500 → 1000. Capture: messages successfully accepted, dropped (server-side rate limit), connection failures, p50/p95/p99 ack latency.

2. **`booking-create.js`** — POST `/booking/requests`. 50 RPS for 2 min. Capture p50/p95/p99 latency, error rate.

3. **`list-conversations.js`** — set up test user with 100 conversations, GET `/chat/conversations?role=customer`. 20 RPS for 1 min. Capture p99 latency (this exercises the N+1).

4. **`available-guards.js`** — set up 200 guards with GPS within 50km radius. GET `/booking/available-guards?lat=...&lng=...&radius_km=50` at 30 RPS. Capture p99 (exercises 5-JOIN Haversine).

5. **`payment-create.js`** — POST `/booking/payments`. 20 RPS. Capture p99 + DB write contention.

6. **`auth-login.js`** — POST `/auth/login/mobile`. 10 RPS. Capture Argon2 verify p99 (CPU-bound, important for sizing).

**Capture into `perf-baseline/results.md`** with table:

| Test | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Error rate | Notes |
|---|---|---|---|---|---|---|

This is the "must not regress" gate. Every phase exit criteria adds: "p99 must be within +20% of baseline".

**Environment note:** if running against local Docker Compose (single Postgres no replica), document that. Numbers will be optimistic vs production. That's fine for relative comparison.

### B2 — PDPA compliance audit

Create `/v1-audit/07-pdpa.md` with:

**§7.1 Personal Data Inventory** — what personal data the system stores:
- `auth.users` — phone, password hash, role, approval_status
- `auth.customer_profiles` — full name, contact phone, email, address, company
- `auth.guard_profiles` — full name, gender, DOB, address, bank account (masked), emergency contact, 5 document images (ID card, security license, training cert, criminal check, driver license)
- `booking.guard_requests` — service address (location)
- `tracking.guard_locations` — real-time GPS
- `tracking.location_history` — GPS history (90-day retention exists ✓)
- `chat.messages` — private message content
- `chat.attachments` — user-uploaded images/videos
- `audit.logs` — user_id, IP per action

For each: classification (sensitive / regular), retention policy (current vs proposed), legal basis under PDPA.

**§7.2 PDPA Rights Coverage** — for each right under Thai PDPA, what's supported:

| Right | Current support | Gap |
|---|---|---|
| §19 Right to access (data export) | ❌ ไม่มี endpoint | ต้องสร้าง `GET /me/data-export` returns JSON of all user data |
| §20 Right to rectification | ✅ partial (profile edit) | guard documents แก้ได้, customer profile แก้ได้ |
| §33 Right to erasure | ❌ ไม่มี delete account flow | ต้องมี soft-delete (PII redact + audit retention) |
| §30 Right to know about processing | ❌ ไม่มี privacy policy in-app | ต้องเพิ่มใน app settings + signup flow |
| §31 Right to withdraw consent | ❌ ไม่มี | per-purpose consent: marketing notification, location sharing, etc. |
| §32 Right to data portability | ❌ ไม่มี | extension of §19 — machine-readable format |
| §34 Notification of data breach | ❌ ไม่มี process | 72-hour notification process to ETDA + affected users |

**§7.3 Retention Policy Gaps:**
- `tracking.location_history` — 90 days ✓ documented
- `audit.logs` — ไม่ระบุ retention. Recommend: 2 years for audit, then archive
- `chat.messages` — ไม่ระบุ. Recommend: indefinite while account active, purge 90 days after account deletion
- `chat.attachments` (S3) — ไม่ระบุ. Recommend: same as messages
- `auth.guard_profiles.id_card_image` etc. — เก็บถาวรขณะบัญชี active, purge 90 days after account deletion
- `auth.otp_codes` — มี cleanup ทุก 1 ชม. ✓

**§7.4 Data Access Audit (PDPA §30):**
Current `audit.logs` table doesn't log GETs/reads. PDPA expects audit trail for who accessed personal data. Gap → add opt-in audit for admin GETs of customer/guard profiles.

**§7.5 Cross-Border Transfer:**
- Cloudflare R2 — where is data stored? If EU/US, need standard contractual clauses or adequacy decision under PDPA §28.
- FCM — Google US — same consideration.
- Document the transfer mechanism.

**§7.6 Top PDPA Risks (ranked):**

| # | Risk | Severity | Fix |
|---|---|---|---|
| 1 | No right-to-erasure endpoint | 🔴 CRITICAL | `DELETE /me` with soft-delete + PII redaction |
| 2 | No data export endpoint | 🔴 CRITICAL | `GET /me/data-export` |
| 3 | No privacy policy in-app | 🔴 CRITICAL | privacy policy page + consent on signup |
| 4 | No breach notification process | 🟠 HIGH | runbook for 72-hour notification |
| 5 | No data access audit | 🟠 HIGH | log admin GETs of personal data |
| 6 | No cross-border transfer documentation | 🟠 HIGH | document R2 + FCM location, SCC |
| 7 | No consent withdrawal | 🟡 MEDIUM | per-purpose consent flags |
| 8 | No retention policy doc | 🟡 MEDIUM | retention matrix |

### B3 — Cost baseline

Create `/v1-audit/cost-baseline.md`:

- Current docker compose resource usage (CPU, RAM per container)
- If deployed to a cloud, estimated monthly cost per service
- Estimate of cost change for v2 (adding NATS, OTel collector, Grafana stack, pgbouncer, read replica = ~+30-50% infra cost)
- One-line per phase: estimated cost delta

If no production deployment exists, just document the resource footprint for planning.

### B4 — Update `00-overview.md`

After Phase 0.5 completes, update §00-overview.md "ไฟล์ที่สร้าง" table to include:

- `07-pdpa.md`
- `perf-baseline/README.md` + `results.md`
- `cost-baseline.md`

---

## Exit Criteria for This Brief

- All 9 audit revisions (A1-A9) applied
- `07-pdpa.md` exists with §7.1-7.6 complete
- `perf-baseline/` has 6 k6 scripts + README + initial results.md
- `cost-baseline.md` exists
- `00-overview.md` updated to reference new files

STOP and report. User will review revised audit + new findings before approving Phase 0 to start.

---

## Quickstart for the user

In existing `claude` session in `/Users/nest/Documents/guard-dispatch/`:

```
Read audit-revisions.md and execute Part A (the 9 revisions). Stop and summarize before moving to Part B.
```

After reviewing revisions:

```
Execute Part B (Phase 0.5 — perf baseline + PDPA audit + cost baseline).
```
