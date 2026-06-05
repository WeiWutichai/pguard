# ROLE_MATRIX — Source of Truth

> **Status:** Active source of truth for role-based access control.
> **Audit basis:** `v2-audit/role-access-audit-raw.md` (Date: 2026-06-03)
> **Companion HTML artifacts:** `docs/reviews/role-access-matrix.html`, `docs/reviews/frontend-backend-permission-mismatch.html`
> **Maintenance:** Update this file when a new endpoint/screen is added or when a role gate changes. Code review must verify changes against this matrix.

---

## Roles

| Role | Scope | Authentication |
|------|-------|---------------|
| **admin** | Web admin only. Full read/write on operational data. | JWT cookie (web) |
| **guard** | Mobile only. Self-scoped read/write on own profile, jobs, earnings, GPS, reviews-received. | JWT Bearer (mobile) |
| **customer** | Mobile only. Self-scoped read/write on own bookings, receipts, reviews-given, payments. | JWT Bearer (mobile) |

## Design principles

1. **Admin = no scope filtering** — admin sees and writes everything.
2. **Guard / customer = self-scoped only** — never see another user's resources unless they share a transaction (chat, call, location).
3. **Participant-based access** — chat, call, location use conversation/assignment membership (NOT pure role check). A user must be a participant in the resource.
4. **Backend is authoritative** — frontend hiding is UX, not security. Every endpoint enforces its own gate.
5. **No upgrade path** — guard cannot self-promote to admin; customer cannot self-promote to guard. Role assignment happens during onboarding via admin approval flow.

## Sidebar / navigation visibility (Web admin)

All 14 sidebar items are admin-only. Gating is **layout-level**:

```
app/(dashboard)/layout.tsx
  ├── RequireAuth         — redirect anonymous to /login
  └── AdminOnly           — show 403 if user.role != "admin"
       └── {children}     — actual pages
```

| # | Item | Route | Visible to |
|---|------|-------|-----------|
| 1 | Home (Dashboard) | `/` | admin |
| 2 | Live Map | `/map` | admin |
| 3 | Operations | `/operations` | admin |
| 4 | Applicants | `/applicants` | admin |
| 5 | Guards | `/guards` | admin |
| 6 | Expiring Docs | `/expiring` | admin |
| 7 | Customers | `/customers` | admin |
| 8 | Reviews | `/reviews` | admin |
| 9 | Chat (admin) | `/chat` | admin |
| 10 | Calls | `/calls` | admin |
| 11 | Wallet | `/wallet` | admin |
| 12 | Pricing | `/pricing` | admin |
| 13 | Tasks | `/tasks` | admin |
| 14 | Reports | `/reports` | admin |
| 15 | Activity Log | `/activity` | admin |
| 16 | Settings | `/settings` | admin |
| 17 | Profile | `/profile` | admin |

> Note: Sidebar.tsx does NOT filter items per role. AdminOnly wrapper makes that unnecessary — non-admin sees a 403 before any sidebar item matters.

## Mobile navigation visibility

### Guard dashboard (bottom tabs)

| Tab | Screen | Visible to |
|-----|--------|-----------|
| Home | GuardHomeTab | guard |
| Jobs | GuardJobsTab | guard |
| Chat | ChatListScreen(actingRole='guard') | guard |
| Income | GuardIncomeTab | guard |
| Profile | GuardProfileTab | guard |

### Customer (hirer) dashboard (bottom tabs)

| Tab | Screen | Visible to |
|-----|--------|-----------|
| Home | ServiceSelectionScreen | customer (approved) |
| Chat | ChatListScreen(actingRole='customer') | customer (approved) |
| History | HirerHistoryScreen | customer (approved) |
| Profile | HirerProfileScreen | customer (approved) |

> **Gate:** `HirerDashboardScreen.initState()` redirects to `CustomerRegistrationScreen` if `customerApprovalStatus != 'approved'`.
> **Gap:** `GuardDashboardScreen.initState()` has no role check (relies on app-root selector in `main.dart`). See Mismatch #1 in mismatch report — fix required.

## Backend API matrix

### Auth service (22 endpoints)

| Method | Path | admin | guard | customer | Public | Notes |
|--------|------|:-----:|:-----:|:--------:|:------:|-------|
| POST | `/register` | ❌ | ❌ | ❌ | ✅ | deprecated; OTP flow preferred |
| POST | `/login` | ✅ | ✅ | ✅ | ✅ | open to authenticate |
| POST | `/login/phone` | ❌ | ❌ | ❌ | ✅ | web cookie-based |
| POST | `/login/mobile` | ❌ | ✅ | ✅ | — | tokens in body |
| POST | `/check-status` | — | — | — | ✅ | open |
| POST | `/otp/request` | — | — | — | ✅ | open |
| POST | `/otp/verify` | — | — | — | ✅ | open |
| POST | `/register/otp` | — | — | — | ✅ | returns 202, no tokens |
| POST | `/refresh` | ✅ | — | — | — | web cookie |
| POST | `/refresh/mobile` | — | ✅ | ✅ | — | mobile body |
| POST | `/logout` | ✅ | ✅ | ✅ | — | revokes jti |
| GET | `/me` | ✅ | ✅ | ✅ | — | self-view |
| PUT | `/me` | ✅ | ✅ | ✅ | — | self-edit |
| POST | `/profile/role` | — | — | — | profile_token | OTP flow or auth Bearer |
| POST | `/profile/reissue` | — | — | — | pending users | open with phone_verified_token |
| POST | `/profile/guard` | — | — | — | profile_token | guard registration |
| POST | `/profile/customer` | — | — | — | profile_token | customer registration |
| POST | `/profile/avatar` | ✅ | ✅ | ✅ | — | any authenticated |
| GET | `/guards/me` | ❌ | ✅ | ❌ | — | guard self-view |
| PUT | `/guards/me` | ❌ | ✅ | ❌ | — | guard self-edit |
| PUT | `/guards/me/expiry` | ❌ | ✅ | ❌ | — | guard self-edit doc expiry |
| PUT | `/profile/guard/document/{type}` | ❌ | ✅ | ❌ | — | guard re-upload doc |
| GET | `/users` | ✅ | ❌ | ❌ | — | admin list |
| GET | `/admin/guards/{id}` | ✅ | ❌ | ❌ | — | admin view guard |
| PUT | `/admin/guards/{id}` | ✅ | ❌ | ❌ | — | admin edit guard |
| GET | `/admin/customers/{id}` | ✅ | ❌ | ❌ | — | admin view customer |
| GET | `/admin/customer-applicants` | ✅ | ❌ | ❌ | — | admin applicants |
| PATCH | `/admin/customers/{id}/approval` | ✅ | ❌ | ❌ | — | admin approve customer |
| PATCH | `/users/{id}/approval` | ✅ | ❌ | ❌ | — | admin approve guard |
| GET | `/admin/audit-logs` | ✅ | ❌ | ❌ | — | admin audit trail |
| GET | `/admin/expiring-docs` | ✅ | ❌ | ❌ | — | admin doc expiry |

### Booking service (42 endpoints — see full list in audit raw)

Key gates:

| Endpoint family | admin | guard | customer | Notes |
|----------------|:-----:|:-----:|:--------:|-------|
| `POST /requests` | — | ❌ | ✅ | customer creates |
| `GET /requests` | ✅ | ❌ | ✅ (own) | scoped read |
| `PUT /requests/{id}/cancel` | ✅ | ❌ | ✅ (owner) | |
| `POST /requests/{id}/assign` | ✅ | ❌ | ✅ (owner of own request) | |
| `GET /requests/{id}/assignments` | ✅ | ✅ (if assigned) | ✅ (owner) | |
| `PUT /assignments/{id}/accept-decline` | ❌ | ✅ | ❌ | guard accept/decline |
| `PUT /assignments/{id}/start` | ❌ | ✅ | ❌ | guard starts |
| `PUT /assignments/{id}/status` | ❌ | ✅ | ❌ | guard updates en_route/arrived |
| `PUT /assignments/{id}/review-completion` | ❌ | ❌ | ✅ | customer approves completion |
| `POST /assignments/{id}/progress` | ❌ | ✅ | ❌ | guard hourly check-in |
| `GET /assignments/{id}/progress` | ✅ | ✅ (assigned) | ✅ (owner) | |
| `POST /payments` | ❌ | ❌ | ✅ | customer pays |
| `GET /assignments/{id}/cost-summary` | ✅ | ✅ (assigned) | ✅ (owner) | |
| `POST /assignments/{id}/tip` | ❌ | ❌ | ✅ | customer tips |
| `GET /customer/receipts` | ❌ | ❌ | ✅ | own receipts |
| `POST /assignments/{id}/review` | ❌ | ❌ | ✅ | customer reviews guard |
| `GET /guards/{id}/reviews` | — | — | — | ✅ public |
| `GET /admin/reviews` | ✅ | ❌ | ❌ | admin moderation |
| `PUT /admin/reviews/{id}/visibility` | ✅ | ❌ | ❌ | hide/show |
| `GET /available-guards` | ❌ | ❌ | ✅ | **GAP:** currently any authenticated — see Mismatch #2 |
| `GET /pricing/services` | — | — | — | ✅ public |
| `POST/PUT/DELETE /pricing/services` | ✅ | ❌ | ❌ | admin CRUD |
| `GET /admin/wallet/summary` | ✅ | ❌ | ❌ | |
| `GET /admin/payments` | ✅ | ❌ | ❌ | |
| `GET /admin/refunds` | ✅ | ❌ | ❌ | |
| `PUT /admin/refunds/{id}/process` | ✅ | ❌ | ❌ | |
| `GET /admin/operations` | ✅ | ❌ | ❌ | |
| `GET /admin/calls` | ✅ | ❌ | ❌ | |
| `GET /guard/dashboard` | ❌ | ✅ | ❌ | |
| `GET /guard/jobs` | ❌ | ✅ | ❌ | |
| `GET /guard/earnings` | ❌ | ✅ | ❌ | |
| `GET /guard/work-history` | ❌ | ✅ | ❌ | |
| `GET /guard/ratings` | ❌ | ✅ | ❌ | |
| `GET /guard/active-job` | ❌ | ✅ | ❌ | |
| `GET /customer/active-job` | ❌ | ❌ | ✅ | |
| `POST /calls/initiate` | — | ✅ (participant) | ✅ (participant) | participant-based |
| `PUT /calls/{id}/accept` | — | ✅ (callee) | ✅ (callee) | |
| `PUT /calls/{id}/reject` | — | ✅ (callee) | ✅ (callee) | |
| `PUT /calls/{id}/end` | — | ✅ (participant) | ✅ (participant) | |
| `GET /calls/{id}` | ✅ | ✅ (participant) | ✅ (participant) | |

### Tracking service (8 endpoints)

| Method | Path | admin | guard | customer | Notes |
|--------|------|:-----:|:-----:|:--------:|-------|
| GET (WS) | `/ws/track` | ❌ | ✅ | ❌ | guard-only GPS write |
| GET | `/locations/all` | ✅ | ❌ | ❌ | admin map |
| GET | `/locations/{guard_id}` | ✅ | ✅ (own only) | ✅ (active booking with that guard) | participant-based |
| GET | `/locations/{guard_id}/history` | ✅ | ✅ (own) | ✅ (active booking) | participant-based |

### Chat service (8 endpoints)

| Method | Path | admin | guard | customer | Notes |
|--------|------|:-----:|:-----:|:--------:|-------|
| GET (WS) | `/ws/chat` | ✅ | ✅ (participant) | ✅ (participant) | |
| POST | `/conversations` | ✅ | ✅ (participant) | ✅ (participant) | |
| GET | `/conversations` | ✅ | ✅ (own list) | ✅ (own list) | self-list, role param |
| GET | `/conversations/{id}/messages` | ✅ | ✅ (participant) | ✅ (participant) | |
| PUT | `/conversations/{id}/read` | ✅ | ✅ (participant) | ✅ (participant) | |
| POST | `/attachments` | ✅ | ✅ (participant) | ✅ (participant) | |
| GET | `/attachments/{id}` | ✅ | ✅ (participant) | ✅ (participant) | signed URL |
| GET | `/admin/conversations` | ✅ | ❌ | ❌ | admin bulk view |

### Notification service (7 endpoints)

| Method | Path | admin | guard | customer | Notes |
|--------|------|:-----:|:-----:|:--------:|-------|
| POST | `/tokens` | ✅ | ✅ | ✅ | register FCM device |
| DELETE | `/tokens` | ✅ | ✅ | ✅ | unregister |
| GET | `/notifications` | ✅ | ✅ | ✅ | own list (scoped by user_id) |
| GET | `/notifications/unread-count` | ✅ | ✅ | ✅ | own badge |
| PUT | `/notifications/read-all` | ✅ | ✅ | ✅ | own |
| PUT | `/notifications/{id}/read` | ✅ | ✅ | ✅ | own |
| POST | `/notifications/send` | ✅ | ❌ | ❌ | admin broadcast |

## Mismatches (active — must fix)

See `docs/reviews/frontend-backend-permission-mismatch.html` for full visual.

| # | Severity | Location | Issue | Fix |
|---|----------|----------|-------|-----|
| 1 | LOW (mitigated) | `frontend/mobile/lib/screens/guard/guard_dashboard_screen.dart:13-18` | No role check in `initState()` | Add `if auth.role != 'guard'` redirect |
| 2 | LOW | `services/booking/src/handlers.rs` `GET /available-guards` | Any authenticated user (intended customer-only) | Add `if user.role != "customer"` check |
| 3 | MEDIUM | `frontend/mobile/lib/screens/chat_list_screen.dart` | `actingRole` param trusted without validation | Validate `actingRole` matches `auth.role` |

## Product decision: should guard access payment/finance?

**Current code follows Option A** — guard sees own earnings (read-only) and tip notifications only. No access to /admin/wallet, /admin/payments, /admin/refunds, /pricing CRUD. No write access to anything monetary except progress reports (which feed proration).

**Recommendation: keep Option A.** Reasons:
- Reduces blast radius if guard credentials compromised
- Removes guard from refund/dispute workflow (admin-mediated is cleaner)
- Tip is the only "guard sees money" surface — already opt-in by customer
- Matches PDPA principle: minimum necessary access

If product later wants Option B (guard can record cash collection on behalf of platform), that requires a separate `cashier` sub-role and a different audit trail. Not in current scope.

---

**Last updated:** 2026-06-03
**Owner:** Architecture team
**Review cadence:** On every PR that adds/removes an endpoint or screen
