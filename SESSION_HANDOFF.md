# Session Handoff — pguard

> **For:** the next Claude session (Cowork or Claude Code CLI) — paste/reference this file to bootstrap context. **Updated:** 2026-06-04.
>
> **You are picking up a v2 redesign project.** Read this top-to-bottom (10 min). The references in §6 will take you the rest of the way.

---

## 1. Project at a glance

**pguard** = clean v2 of an existing real-time security guard dispatch SaaS (Thai market). v1 lives at `../guard-dispatch/` (read-only reference). pguard will become the canonical repo after Phase 0 cleanup completes inside `guard-dispatch/` and that folder is renamed.

- **Domain:** "Grab for security guards" — customer books on-demand guard via mobile, guard accepts/navigates/checks-in hourly, customer rates after. Admin operates from web.
- **Tech stack (locked):** Rust microservices (Axum 0.8) + Flutter mobile (Riverpod 2.x) + Next.js 16 App Router + PostgreSQL + NATS + Redis + MinIO/R2.
- **Production users:** zero — dev/staging only. No backward-compat burden.

---

## 2. What this session accomplished (chronological)

1. **Claude Design output** — 40 HTML pages covering 95/101 backend endpoints + Coverage Matrix (verifier ran). Saved at `redesign-pguard/project/pguard/`.
2. **pguard environment skeleton** — CLAUDE.md, README, .gitignore, `.claude/` (settings, hooks pre-tool/post-edit, 4 subagents with memory bundles, INSTALL-SKILLS).
3. **v1 architecture audit (Phase 1)** — 7 files in `v1-audit/` produced by Claude Code CLI using Explore agents. Findings: 5 structural issues, 15 ranked security risks, critical test gaps, 6-phase migration plan (strangler-fig).
4. **Audit revisions (Part A — 9 fixes applied)** — production-user assumption corrected, PIN math fixed (single IP vs distributed), per-service labels reframed, Phase 3 split order changed (call → payment → rating → assignment), API versioning policy added, schema separation roadmap, operational maturity gaps (§5.7), Phase 0.5 inserted, risk table updated.
5. **Role access audit (Layer 1-5 ground truth)** — 87 backend endpoints + 38 frontend surfaces scanned. Output: `v1-audit/role-access-audit-raw.md`. 3 mismatches found.
6. **Role docs (HTML-first workflow)** — `docs/ROLE_MATRIX.md` (source of truth) + `docs/reviews/role-access-matrix.html` + `docs/reviews/frontend-backend-permission-mismatch.html`.
7. **All planning docs migrated into pguard** — pguard is self-contained now; no need to flip between repos for context.

---

## 3. Locked decisions (do not re-litigate)

| Area | Decision | Source |
|---|---|---|
| Project name | `pguard` (no hyphen, lowercase) | user 2026-06-03 |
| Folder layout | `/Users/nest/Documents/pguard/` sibling of `guard-dispatch/`; rename guard-dispatch later | CLAUDE.md |
| Migration strategy | Strangler-fig as discipline (not user-availability constraint) | v1-audit/05 §5.1 |
| Event bus | **NATS JetStream** | user 2026-06-03 |
| Cross-tx consistency | Transactional outbox | v1-audit/05 §5.4 |
| Service auth (internal) | Service-JWT, separate `SERVICE_JWT_SECRET` | v1-audit/03 #9 |
| API contracts | OpenAPI 3.1 source-of-truth, codegen Rust stubs + Dart + TS | v1-audit/05 §5.4 |
| API versioning | `/v1/` prefix at gateway, per-resource bump for breaking changes | v1-audit/05 §5.4 |
| Flutter state | **Riverpod 2.x + codegen** (no Provider in new code) | user 2026-06-03 |
| Mobile real-time | WebSocket subscription for booking/assignment status (replace 13 polling timers) | v1-audit/02 §2.4 |
| Token revocation | `token_revocation_version` per-user + jti blocklist | v1-audit/03 #1 |
| Refresh rotation | Family + rotation_id (RFC 6749 §6) reuse detection | v1-audit/03 #3 |
| API gateway | Scaffold in Phase 2 — Rust + Axum-as-gateway | user 2026-06-03 |
| Strangler-fig dual-write | **Only where it reduces real risk** — skip when overhead has no payoff (no prod users) | A1 revision |
| PoC service | **NOT** consolidate notification+chat into messaging — keep them separate, just decouple via events | audit override of original brief |
| Phase 3 split order | call → payment → rating → assignment (call most isolated → assignment last) | A4 revision |
| HTML-first workflow | Markdown = source of truth + contracts; HTML = visual review artifacts; product code = real implementation | user 2026-06-04 |
| Role policy — Option A | Guard stays out of money flows (read own earnings + tip notifications only; no /admin/wallet, /admin/refunds, /pricing CRUD) | ROLE_MATRIX.md |

---

## 4. Active todos (priority order)

### 🔴 Now — Phase 0.5 execution (Part B of audit-revisions.md)

Brief: `audit-revisions.md` Part B. Execute in Claude Code CLI inside `guard-dispatch/`.

- [ ] **B1** — `v1-audit/perf-baseline/` with 6 k6 scripts (gps-websocket, booking-create, list-conversations, available-guards, payment-create, auth-login) + `README.md` + `results.md`. Numbers become "must not regress > +20%" gate.
- [ ] **B2** — `v1-audit/07-pdpa.md` (§7.1-7.6: personal data inventory, PDPA §19/20/30/31/32/33/34 rights matrix, retention gaps, data-access audit, cross-border R2/FCM, top 8 risks)
- [ ] **B3** — `v1-audit/cost-baseline.md` (current docker compose footprint per container + estimated +30-50% delta for NATS/OTel/Grafana/pgbouncer/replica)
- [ ] **B4** — Update `v1-audit/00-overview.md` "ไฟล์ที่สร้าง" table to reference new files

### 🟠 Next — Role mismatch fixes (decision pending)

3 mismatches identified in `docs/reviews/frontend-backend-permission-mismatch.html`. **User asked to fix but session ended before approval.** Options to re-confirm:

- **A** — Fix all 3 now + 2 bonus (LiveMapScreen role check, explicit `POST /payments` role check) + add regression tests + run `cargo test` + `flutter test`
- **B** — Fix #3 only (MEDIUM — chat actingRole — has real backend gap; #1 #2 are LOW)
- **C** — Defer all until Phase 0 — fold into the cleanup work

Recommendation: **B then A in same Phase 0 cleanup PR.** Tests are cheap to add and high-leverage.

Files to touch:
- `frontend/mobile/lib/screens/chat_list_screen.dart` — add `actingRole` assertion in constructor + `initState` cross-check
- `services/chat/src/handlers.rs` — `list_conversations` reject `?role=` mismatch with JWT role (admin exempt)
- `services/booking/src/handlers.rs` — `available_guards()` add `if user.role != "customer" return Forbidden`
- `services/booking/src/handlers.rs` — `create_payment()` add explicit customer-only check
- `frontend/mobile/lib/screens/guard/guard_dashboard_screen.dart` — `initState` defensive role redirect
- `frontend/mobile/lib/screens/live_map_screen.dart` — `initState` reject guards/unauthenticated

### 🟢 Later — Phase 0 (Stabilize & Safety Net)

After Phase 0.5 produces baselines. Brief: `v1-audit/06-migration-plan.md` Phase 0.

- [ ] Proration unit tests (`compute_proration`, `prorate_payment_in_tx`)
- [ ] `GpsUpdate::validate()` unit tests
- [ ] Cross-service jti revocation integration test
- [ ] nginx `s3_limit 10r/s` on `/minio-files/` (v1-audit/03 #4)
- [ ] nginx `admin_limit 5r/s` on `/booking/admin/*` (#5)
- [ ] Verify WS 1/sec GPS drop is working (already confirmed exists at `services/tracking/src/handlers.rs:54-55`)
- [ ] Split CI into unit + integration jobs; add `flutter test`; add `docker-compose.test.yml`
- [ ] Delete 3 orphan Flutter screens (`set_password`, `registration_role`, `customer_login` — ~600 LOC)
- [ ] Consolidate 2 `guard_registration_screen` files
- [ ] Add notification_logs `(user_id, sent_at)` index (verify via `CREATE INDEX CONCURRENTLY`)

Phase 0 exit criteria: money/safety path has tests, CI shows 2 green jobs (unit+integration+flutter), orphans deleted.

**After Phase 0 done:** rename `guard-dispatch/` → `pguard/` (git history preserved); future Phases 1–5 live entirely in pguard.

---

## 5. Pending product decisions (not blocking — but document when answered)

| # | Question | Where it gets answered |
|---|---|---|
| 1 | Should admin be able to call `GET /available-guards`? Pro: dedicated live-map workflow. Con: admin has `/admin/operations` + `/locations/all`. **Recommended: customer-only.** | When Mismatch #2 is fixed |
| 2 | Should admin be able to `?role=guard\|customer` impersonate in chat list? Needed for admin chat moderation viewport. **Recommended: yes for admin, no for others.** | When Mismatch #3 is fixed |
| 3 | Pact contract testing tool: pact-rust vs Spring Cloud Contract? | Phase 1 messaging service contract setup |
| 4 | k6 baseline environment: local docker-compose (optimistic) vs staging-equivalent? Both? | Phase 0.5 B1 README |
| 5 | R2 datacenter region (PDPA §28 cross-border consideration) | Phase 0.5 B2 §7.5 |

---

## 6. File map — where everything lives

### Planning + decisions (Markdown source of truth)
- `CLAUDE.md` — architecture spec + locked decisions + do/don't rules (≤ 400 lines)
- `README.md` — repo orientation + tree map
- `pguard-brief.md` — original 3-phase Claude Code CLI brief (Phase 1 audit + Phase 2 scaffold + Phase 3 PoC). Phase 1 done; Phases 2-3 pending.
- `audit-revisions.md` — Part A (9 audit revisions) **done** + Part B (Phase 0.5 execution) **pending**
- `docs/ROLE_MATRIX.md` — canonical RBAC source of truth for admin/guard/customer

### Audit (v1 ground truth — basis for v2 decisions)
- `v1-audit/00-overview.md` — exec summary + metrics + risk table (start here)
- `v1-audit/01-current-state.md` — service inventory, coupling, debt hotspots
- `v1-audit/02-issues.md` — architectural issues ranked
- `v1-audit/03-security.md` — JWT/PIN/audit gaps + top 15 risks (with PIN math A2 corrected)
- `v1-audit/04-tests.md` — coverage gaps (P0 critical)
- `v1-audit/05-recommendations.md` — per-service redesign vs port + §5.4 versioning + §5.7 ops gaps
- `v1-audit/06-migration-plan.md` — 6 phases (+ Phase 0.5) strangler-fig
- `v1-audit/role-access-audit-raw.md` — ground-truth role audit, file:line citations

### HTML visual artifacts (review / communication)
- `docs/reviews/role-access-matrix.html` — KPI strip + 5 layers + 87 endpoints + color states
- `docs/reviews/frontend-backend-permission-mismatch.html` — 3 mismatches with before/after diffs + fix priority

### Hi-fi design output (Claude Design)
- `redesign-pguard/project/pguard/` — 40 HTML pages
  - `Design System.html` — color tokens, typography, components
  - `Coverage Matrix.html` — 95/101 endpoints → screen mapping
  - `Web Admin Live Map.html` — admin hero screen
  - `Mobile - Active Standby.html` — sticky resume card (11 states + 5 surfaces)
  - 22 admin pages + 12 mobile showcase pages + tokens.css + admin.css + admin-shell.js

### Claude Code environment (`.claude/`)
- `settings.json` — hooks config
- `INSTALL-SKILLS.md` — instructions for `npx skills add thananon/9arm-skills`
- `hooks/pre-tool.sh` — blocks 30+ destructive bash patterns
- `hooks/post-edit.sh` — auto fmt/clippy/dart-analyze/eslint + unwrap/Provider/localStorage warnings
- `agents/code-reviewer.md` — 7-section checklist, project-specific
- `agents/security-reviewer.md` — maps to v1 top-15 risks
- `agents/test-writer.md` — P0/P1/P2 priorities for Rust + Flutter
- `agents/architecture-guardian.md` — **NEW** — 10 hard rules + 4 soft rules (prevents god-service regrowth, cross-schema writes, Provider regress, polling regression)
- `agent-memory/<agent>/` — 4 knowledge bundles, 4 files each

### v1 reference (read-only, will become pguard after Phase 0)
- `../guard-dispatch/` — actual v1 code (Rust services, Flutter mobile, Next.js web admin, CLAUDE.md)

---

## 7. How to continue

### From Cowork (new chat in this same desktop app)

Open a new chat with the folder `/Users/nest/Documents/pguard/` connected. Paste this:

```
Read SESSION_HANDOFF.md to bootstrap context. Then continue per §4 priority order — start with whichever item I confirm.
```

### From Claude Code CLI

```bash
cd /Users/nest/Documents/pguard
npx skills add thananon/9arm-skills    # one-time, if not done
claude
```

Then in the session:

```
Read SESSION_HANDOFF.md, CLAUDE.md, and audit-revisions.md Part B. We are starting Phase 0.5 — execute B1 (perf-baseline scripts), B2 (07-pdpa.md), B3 (cost-baseline.md), B4 (update 00-overview). Stop and summarize after each step for review.
```

### Common alternative starts

- **"Fix the 3 role mismatches"** → `docs/reviews/frontend-backend-permission-mismatch.html` shows before/after diffs; fix in `../guard-dispatch/services/` and `../guard-dispatch/frontend/mobile/lib/screens/`
- **"Run the Phase 0 cleanup"** → `v1-audit/06-migration-plan.md` Phase 0; safe to start in parallel with Phase 0.5
- **"Apply the Claude Design output as the new UI"** → `redesign-pguard/project/pguard/` has all 40 HTML pages; use `Design System.html` as token reference

---

## 8. Quick sanity check for the next session

Run these to verify the workspace is intact:

```bash
ls /Users/nest/Documents/pguard          # expect: CLAUDE.md, README, pguard-brief.md, audit-revisions.md, v1-audit/, docs/, redesign-pguard/, .claude/
cat /Users/nest/Documents/pguard/v1-audit/00-overview.md | head -30
ls /Users/nest/Documents/pguard/redesign-pguard/project/pguard/ | wc -l   # expect: 46 (40 HTML + assets)
ls /Users/nest/Documents/pguard/.claude/agents/                            # expect: 4 .md files
cd /Users/nest/Documents/pguard && git status                              # expect: clean or known uncommitted
```

If any of these fail, the workspace was modified after this handoff — read git log and current state before continuing.

---

## 9. Open external loops (things you might encounter)

- **Claude Design tab** may still be open in browser — last Mobile Active Standby prompt is `Done`; output is at `redesign-pguard/project/pguard/Mobile - Active Standby.html`. No further design tasks queued unless user requests.
- **Claude Code CLI session** for `guard-dispatch/` — used for Part A audit revisions (done) and may be reusable for Part B Phase 0.5. Session state not preserved across machine reboots; safe to start fresh.

---

**End of handoff. Welcome to pguard.**
