# Web-admin screens → backend endpoint map

> Generated 2026-06-14 by a fan-out audit (supply: endpoint+real admin-scope per service · demand: design mockups in `redesign-pguard/`). Source of truth for the web-admin rebuild build order.

## TL;DR

- **Real admin cross-user endpoints that exist today:** only `adminListGuardProfiles` (+approve/reject) and rating `listAdminReviews`/`setReviewVisibility`. Plus single-resource admin reads (`getBooking`/`getPayment`/`getCall`/`listMessages`/`getGuardHistory`…). **No admin cross-user LIST for bookings / payments / customers / calls / conversations.**
- **0 of 16** screens are buildable with zero backend work. 3 partial · 8 need new endpoint · 5 fully blocked.
- **Keystone endpoints (unlock the most):** `adminListBookings` + `adminAssignGuard` (→ bookings, tasks, operations) · `adminListCustomerProfiles` (→ customers + customer-name joins) · `adminListPayments` (→ wallet) · `adminListCalls` / `adminListConversations` (→ calls, chat).
- **2 design-vs-architecture conflicts to DECIDE before building:** wallet (v2 refunds are auto/event-driven; design wants a manual approval queue) · pricing (v2 prices server-side at charge; design wants an admin rate catalog). automation is forward-looking (no rule engine).

## Status table

| Screen | Status | Effort | Existing endpoints | New endpoints needed |
|---|---|---|---|---|
| **operations** | 🟢 Partial | L | `listProgressReports`, `getGuardLocation`, `getBooking`, `listLocations` | `adminListActiveBookings`; `nudgeGuard` |
| **profile** | 🟢 Partial | M | `me`, `logout` | `revokeAllSessions`; `listSessions`; `updateAccount`; `enroll2FA` |
| **replay** | 🟢 Partial | M | `getGuardHistory`, `getGuardLocation`, `listProgressReports`, `getBooking` | `getGuardHistoryRange`; `exportGuardHistoryGeoJSON` |
| **bookings** | 🟡 Needs new | L | `getBooking`, `listProgressReports`, `getGuardLocation` | `adminListBookings`; `adminAssignGuard`; `adminGetCustomerProfile` |
| **broadcast** | 🟡 Needs new | M | `sendNotification` | `broadcastNotification`; `audienceCounts`; `listBroadcasts`; `adminSearchUsers` |
| **calls** | 🟡 Needs new | L | `getCall` | `adminListCalls`; `adminCallEvents`; `adminCallStats` |
| **chat** | 🟡 Needs new | L | `listMessages`, `getAttachment` | `adminListConversations`; `flagMessage`; `adminBlockUser`; `adminChatStats` |
| **customers** | 🟡 Needs new | L | — | `adminListCustomerProfiles`; `adminCustomerBookingStats`; `adminCustomerSpendStats`; `adminCustomerKpis` |
| **pricing** | 🟡 Needs new | M | — | `adminListServices` |
| **tasks** | 🟡 Needs new | L | `cancelBooking`, `completePayment` | `adminListBookings`; `adminAssignGuard`; `adminRefund`; `adminGetCustomerProfile` |
| **wallet** | 🟡 Needs new | L | `getPayment`, `completePayment` | `adminListPayments`; `adminListRefunds`; `adminProcessRefund`; `adminWalletKpis` |
| **activity** | 🔴 Blocked | L | — | `adminListActivity` |
| **automation** | 🔴 Blocked | L | — | `listRules` |
| **expiring** | 🔴 Blocked | L | — | `adminListExpiringDocuments`; `sendRenewalReminder` |
| **recruit** | 🔴 Blocked | L | `adminListGuardProfiles`, `adminApproveGuard`, `adminRejectGuard` | `listCandidates` |
| **reports** | 🔴 Blocked | L | — | `reportRevenueTrend`; `reportBookingsByService`; `reportGuardUtilization`; `reportRetentionCohort` |

## Recommended build order

1. replay — most-backed of the unbuilt screens: getGuardHistory (admin reads any guard) + getGuardLocation + admin-readable listProgressReports already supply the track + check-in checkpoints; only speed/heading-per-point and GeoJSON export are minor gaps to derive/drop
2. operations — composite live-ops is mostly present per-booking (listProgressReports admin-read, listLocations/getGuardLocation, sendNotification for Nudge); only ONE new endpoint (adminListActiveBookings) gates the card grid, everything else composes
3. profile — the identity-card + Sign-out-all spine is real (me + logout + conceptual force-revoke-all needing a thin wrapper); ship that real and stub the session-list/2FA/API-token/password surfaces — fastest partial-real demo
4. bookings — the keystone admin list; needs adminListBookings + adminAssignGuard + a customer-name read, but it unlocks the highest-value operator surface and the assign mutation is the platform's core admin job
5. tasks — reuses the SAME adminListBookings + adminAssignGuard from bookings (all-status variant + calendar grouping + bulk Cancel via existing cancelBooking), so it is near-free once bookings backend lands
6. customers — needs a new adminListCustomerProfiles (mirror of the existing adminListGuardProfiles pattern) but the per-customer spend/booking aggregates + KPIs + suspend are heavier; do the bare list first, aggregates later
7. broadcast — single new bulk-send + audience-count + sent-history; no rich read model, leans on the existing admin-only sendNotification pattern, so moderate effort with clear demo payoff
8. calls — the Call row model fully exists (getCall) so adminListCalls is a straightforward list add for the table; the rich timeline/ICE/debug-modal needs a new events store, so ship the table first and defer the modal
9. chat — admin can already read any thread (listMessages/getAttachment bypass); add adminListConversations for the entry list, then layer flag/delete/block/archive moderation mutations — read-pane is half-backed already
10. wallet — needs new bulk ledger + refund queue + manual-process endpoints AND first requires resolving the design-vs-architecture conflict (v2 refunds are automatic/event-driven; the design wants a manual approval queue) before any build
11. reports — four brand-new cross-service analytics endpoints (revenue/service-mix/utilization/retention) plus a service_type dimension the Booking model lacks; pure aggregation work, no reuse, high backend cost
12. expiring — fully-blocked on schema: profile has document-KEY columns but NO expiry_date or last_reminded_at; needs a migration + new admin documents-by-expiry endpoint before any data exists
13. activity — fully-blocked: no cross-service audit/activity feed or store exists (only PDPA access_audit rows, not the business-action feed); needs a new event-sink + read endpoint
14. recruit — fully-blocked on the 5-stage pipeline (no candidate/recruitment endpoints exist at all); only the last two columns map to existing approve/reject, so it needs a whole new recruitment service
15. automation — fully-blocked: no rule engine, storage, or CRUD; forward-looking design where triggers/actions only conceptually map to NATS events — ship as documented API-gap, build last
16. **pricing** — new service-catalog CRUD; first decide whether the charge path should read rates from the catalog (architecture change). Insert near reports/wallet (policy-gated).

## Per-screen detail

### operations — 🟢 Partial (effort L)
- **Existing usable:** `listProgressReports`, `getGuardLocation`, `getBooking`, `listLocations`
- **NEW** [booking] `adminListActiveBookings` — GET /admin/bookings?status=en_route,arrived,started,pending_completion returning Booking[] cross-user (id, customer_id, guard_id, status, address, scheduled_at, hours, work_started_at) — there is NO admin booking-list today; listBookings is owner-scoped and listOpenBookings only returns UNASSIGNED requested jobs
- **NEW** [notification] `nudgeGuard` — reuse sendNotification (POST /notifications/send, admin-only) to push a reminder to the guard — already exists
- **Why:** The composite live-ops shape is mostly present per-booking: listProgressReports (admin-read, check-ins+photo+GPS+missed), getGuardLocation/listLocations (admin live GPS + is_live freshness), getBooking. 'Nudge guard' maps to existing admin-only sendNotification. The ONE hard blocker is the entry list: cards key off IN-PROGRESS states (en_route/arrived/started/pending_completion) but no admin endpoint lists active bookings cross-user (listBookings binds caller user_id; listOpenBookings is unassigned-requested-only). Overdue/elapsed/suggested-refund are derived client-side. Add adminListActiveBookings and the rest composes; effort L because it joins booking+presence+progress across services per card.

### profile — 🟢 Partial (effort M)
- **Existing usable:** `me`, `logout`
- **NEW** [identity] `revokeAllSessions` — POST /auth/revoke-all (admin self force-revoke-all) — force-revoke-all exists CONCEPTUALLY (token_revocation_version bump + jti blocklist, internalRevokeAll) but only as a service-internal/event path, not a self-serve client endpoint; needs a thin edge wrapper for 'Sign out all'
- **NEW** [identity] `listSessions / revokeSession` — GET /auth/sessions returning device/browser/IP/city/last-active rows + DELETE /auth/sessions/{id} — identity tracks refresh-token FAMILIES + jti blocklist but exposes no session-list or per-session-revoke (only logout-current + revoke-all)
- **NEW** [identity] `updateAccount / changePassword` — PATCH /auth/me {full_name,email} + POST /auth/change-password — /auth/me is read-only (GET id+role); only deleteMe + dataExport exist on /me
- **NEW** [identity] `enroll2FA / apiTokens` — 2FA enroll/verify/disable + personal API-token list/create/revoke (pg_live_*) — neither exists in v2
- **Why:** MIXED. SUPPORTED today: GET /auth/me backs the identity card (but only returns user_id+role — name/email/last-login/role-label are NOT in the token claims, so even the card needs richer /auth/me or a profile read). logout backs sign-out-current. Force-revoke-all exists conceptually (internalRevokeAll/token_revocation_version) and just needs a self-serve edge wrapper for 'Sign out all'. GAPS: no session-LIST or per-session revoke (families+jti tracked but not exposed as device/IP/city rows), no API-token endpoints, no 2FA, no PATCH account/change-password on /auth/me, no personal activity feed. Classified partial (not fully-blocked) because the identity-card + sign-out-all spine is real; the rest is account-management surface to add.

### replay — 🟢 Partial (effort M)
- **Existing usable:** `getGuardHistory`, `getGuardLocation`, `listProgressReports`, `getBooking`
- **NEW** [presence] `getGuardHistoryRange` — GET /guards/{id}/history?from=&to= returning HistoryPoint[] with added speed+heading per point (currently only lat/lng/accuracy/recorded_at)
- **NEW** [presence] `exportGuardHistoryGeoJSON` — GET /guards/{id}/history.geojson?from=&to= returning a GeoJSON FeatureCollection (optional; client can transform instead)
- **Why:** Most-backed of the un-built screens. getGuardHistory is admin-allowed (admin reads ANY guard) and returns the GPS track; getGuardLocation gives the latest point WITH speed/heading/is_online. Check-in checkpoints (done/missed/pending, hourly 'ตรวจรอบ N') come from listProgressReports which is admin-readable per booking, joined client-side. Three real gaps, all minor/derivable: (1) HistoryPoint has NO per-point speed/heading so the info-card values must be read from the latest GuardLocation or dropped, (2) no from/to time-window param (history is newest-first paginated, must filter by recorded_at client-side), (3) no GeoJSON export (transform client-side). booking->guard resolution needed because history is keyed by guard_id not booking_id. Buildable as a real screen with derive/drop on speed+heading.

### bookings — 🟡 Needs new (effort L)
- **Existing usable:** `getBooking`, `listProgressReports`, `getGuardLocation`
- **NEW** [booking] `adminListBookings` — GET /admin/bookings?status=&search=&limit=&offset= returning {data: Booking[], total} cross-user (id, customer_id, guard_id, status, scheduled_at, base_fee/total, hours, guard_count, address) — NO admin booking-list exists; listBookings is WHERE customer_id=$1 OR guard_id=$1
- **NEW** [booking] `adminAssignGuard` — POST /admin/bookings/{id}/assign {guard_id} setting guard_id + status=assigned, emitting an assignment event — v2 has NO /assign endpoint at all (acceptBooking self-assigns the calling guard, not an admin-pick)
- **NEW** [profile] `adminGetCustomerProfile` — GET /admin/customer-profiles/{user_id} (or batch) returning full_name+address so the list can show customer name + drawer address — Booking carries only customer_id; getMyProfile/upsertCustomerProfile are self-scoped
- **Why:** Core demand is an admin cross-user booking list joined to customer name + assigned-guard name + the assign mutation. None exist: listBookings is owner-scoped (admin sees only bookings they participate in), there is NO /assign in v2 (acceptBooking is guard-self-assign), and customer name needs a profile read keyed by customer_id (no admin customer-profile fetch). Guard name can lean on adminListGuardProfiles (cross-user, has user_id) but customer name has no admin source. getBooking gates 403 for non-participant admins so even per-row drill-down needs the new list/admin-read. Three new endpoints across two services.

### broadcast — 🟡 Needs new (effort M)
- **Existing usable:** `sendNotification`
- **NEW** [notification] `broadcastNotification` — POST /admin/broadcast {audience: all|guards|customers|user_id, type, title, body, schedule: now|datetime} fanning out to a whole role — sendNotification targets ONE req.user_id only, no bulk/audience fan-out
- **NEW** [notification/profile] `audienceCounts` — GET /admin/audience-counts returning {all, guards, customers} recipient totals — no role-count endpoint exists
- **NEW** [notification] `listBroadcasts / saveDraft / scheduleBroadcast` — GET /admin/broadcasts (sent history: title, audience label, recipient_count, type, sent_at) + draft/schedule storage — none exist
- **NEW** [profile/identity] `adminSearchUsers` — GET /admin/users/search?q= for the specific-user target picker
- **Why:** sendNotification is admin-only but single-target (one user_id, returns the one log it created) and has NO bulk-retrieval. The composer needs: an audience-count endpoint (all/guards/customers totals), a broadcast/bulk-send accepting audience+type+title+body+schedule, save-draft, schedule-later, a sent-campaign history list, and user-search for specific-target. The v2 notification service is a per-user read feed + service-JWT producer ingress; none of the broadcast surface exists. Effort M (no rich read model like calls, just outbound fan-out + counts).

### calls — 🟡 Needs new (effort L)
- **Existing usable:** `getCall`
- **NEW** [calling] `adminListCalls` — GET /admin/calls?status=&type=&search=&limit=&offset= returning {data: Call[], total} cross-user (id, caller_id, callee_id, call_type, duration_seconds, status, started_at) — only single-row getCall (admin bypass) exists; NO list-calls anywhere
- **NEW** [calling] `adminCallEvents` — GET /admin/calls/{id}/events returning a per-call timeline (initiated/ringing/accepted/connected/ended with ms timestamps) + ICE state + signal quality + raw WebRTC/signaling debug log — none of this is persisted; v2 calling is a plain SDP/ICE relay
- **NEW** [calling] `adminCallStats` — GET /admin/reports/calls/kpis returning {calls_today, connect_rate, avg_duration, missed}
- **Why:** The Call row model exists (getCall returns every field the table needs) but is single-resource-only — there is NO list endpoint, so the table itself is unbuildable. caller/callee are IDs needing name resolution (cross-service). The detail modal is far richer than anything stored: per-call event timeline with ms timestamps, ICE state, signal quality, and a raw WebRTC debug log require a call-events read model the relay-only calling service does not keep. KPIs need a stats endpoint. Needs a call_logs/events persistence layer added, not just an endpoint.

### chat — 🟡 Needs new (effort L)
- **Existing usable:** `listMessages`, `getAttachment`
- **NEW** [chat] `adminListConversations` — GET /admin/conversations?flagged=&search= returning {data: Conversation[], total} cross-user (id, request_id+status, participants names+roles, last_message, flagged_count) — listConversations binds caller user_id with NO admin branch; admin sees only own threads
- **NEW** [chat] `flagMessage / listFlaggedMessages / deleteMessage` — per-message flag/report store + DELETE /admin/messages/{id} — no flag column or moderation delete exists
- **NEW** [chat] `adminBlockUser / archiveConversation` — POST /admin/users/{id}/block, PUT /admin/conversations/{id}/archive — no block/archive concept exists
- **NEW** [chat] `adminChatStats` — GET /admin/reports/chat/kpis returning {messages_today, flagged_count, avg_response_time}
- **Why:** Admin can READ any single conversation's messages (listMessages admin-bypass) and any attachment (getAttachment admin-bypass), so the read-pane is half-backed once you know a conversation_id. But there is NO admin list-all-conversations (listConversations is participant-scoped, no admin branch), no per-message flag/report store, no delete-message, no block-user, no archive, and no chat KPIs. Read-only by design (admins can't send). The entry list + all moderation mutations + flag model + stats are unbacked. Strong API-gap.

### customers — 🟡 Needs new (effort L)
- **Existing usable:** —
- **NEW** [profile] `adminListCustomerProfiles` — GET /admin/customer-profiles?type=&search=&limit=&offset= returning {data: CustomerProfile[], total} cross-user (user_id, full_name, address, customer_type, approval_status, created_at) — mirror of adminListGuardProfiles which exists; NO customer equivalent exists
- **NEW** [booking] `adminCustomerBookingStats` — GET /admin/customers/{id}/stats (or batched) returning {booking_count} per customer — booking has no per-customer aggregate for admins
- **NEW** [payment] `adminCustomerSpendStats` — GET /admin/customers/{id}/spend returning {total_spend, payment_method} — listPayments is caller-scoped
- **NEW** [booking/payment] `adminCustomerKpis` — GET /admin/reports/customers/kpis returning {total_customers, monthly_spend, total_bookings, repeat_rate}
- **Why:** Profile only exposes self POST /profile/customer + self GET /profile/me; there is NO admin customer-list (unlike guards which HAVE adminListGuardProfiles). Beyond the bare list the design wants cross-service aggregates with no source: booking-count + total-spend per customer (booking+payment, both owner-scoped today), payment method, approval timeline, account-quality classification (good/watch/new — a DERIVED label with no field), plus 4 KPI rollups and a suspend mutation (deleteMe is self-only; no admin suspend). Stub already correctly documents the bare gap; reality needs an admin customer-list PLUS several aggregate endpoints. Heaviest profile-side gap.

### pricing — 🟡 Needs new (effort M)
- **Existing usable:** —
- **NEW** [payment (or new pricing svc)] `adminListServices / adminCreateService / adminUpdateService / adminDeactivateService` — GET /v1/pricing/services + POST/PUT/DELETE /v1/admin/pricing/services returning {id, name_th, name_en, base_fee, min_hours, notes, status}
- **Why:** v2 computes price server-side at charge time (expected_total = base_fee×hours×guards+tip); base_fee is a server-owned per-booking column, there is NO admin-managed service-rate catalog/CRUD. Design wants a Services-tab CRUD (name TH/EN, base_fee ฿/hr, min_hours, notes, active). Needs a new service-catalog table + CRUD AND a decision: should the charge path read rates from this catalog? (architecture change, like wallet auto-refund). Price Rules tab = future/coming-soon, no data.

### tasks — 🟡 Needs new (effort L)
- **Existing usable:** `cancelBooking`, `completePayment`
- **NEW** [booking] `adminListBookings` — GET /admin/bookings?status=&search=&limit=&offset= returning {data: Booking[], total} across ALL statuses cross-user — same missing endpoint as bookings screen, with all-status + Unassigned filter + scheduled_at for the calendar grouping
- **NEW** [booking] `adminAssignGuard` — POST /admin/bookings/{id}/assign {guard_id} (bulk-callable) — no /assign exists
- **NEW** [payment] `adminRefund` — POST /admin/payments/{id}/refund or reuse completePayment (POST /payments/{booking_id}/complete, admin-only, proration override) — completePayment exists but is proration-finalize not arbitrary admin refund-with-bank-slip
- **NEW** [profile] `adminGetCustomerProfile` — GET /admin/customer-profiles/{user_id} for customer-name column
- **Why:** Same backbone gap as bookings (no admin booking-list, no /assign) plus a calendar grouping by scheduled_at and three BULK mutations. Assign and the customer-name join are missing exactly as in bookings. Bulk Cancel maps to the existing admin-overridable cancelBooking (per-id, loop) and bulk Refund can partly lean on the admin-only completePayment proration override, but a clean bulk admin booking-list + assign are the blockers. Cancel is PRE-ARRIVAL-only so bulk cancel only legal on early-state rows. Effort L.

### wallet — 🟡 Needs new (effort L)
- **Existing usable:** `getPayment`, `completePayment`
- **NEW** [payment] `adminListPayments` — GET /admin/payments?status=&search=&limit=&offset= returning {data: Payment[], total} cross-user ledger (id, customer_id, guard_id, amount, status paid|authorized|refunded|failed, txn_ref, paid_at) — listPayments is WHERE customer_id=$1, admin sees only own; no bulk admin ledger
- **NEW** [payment] `adminListRefunds` — GET /admin/refunds?status=pending|processed|skipped returning refund queue rows (payment_id, customer, guard, amount_paid, refund_amount, reason) — refunds are automatic/event-driven in v2; no pending-queue concept exists
- **NEW** [payment] `adminProcessRefund` — PUT /admin/refunds/{id}/process {bank_slip_ref, notes} and /skip — completePayment finalizes proration but has no bank-slip/skip/manual-approval workflow
- **NEW** [payment] `adminWalletKpis` — GET /admin/reports/wallet/kpis returning {pending_refunds_amount+count, refunded_this_month, monthly_volume, skipped_count}
- **Why:** DESIGN-vs-ARCHITECTURE CONFLICT to flag, not just missing endpoints. v2 deliberately made refunds AUTOMATIC/event-driven (payment consumer finalizes proration, emits payment.refund_processed, no admin step). The design presents the opposite: a MANUAL admin refund-approval queue (pending->confirm-with-bank-slip->skip) with refund statuses pending/processed/skipped and payment statuses paid/authorized/refunded/failed that don't all exist on the Payment model. getPayment (admin single-row) and completePayment (admin proration override) are the only real admin hooks; the bulk ledger, refund queue, manual process/skip, bank-slip persistence, and KPIs are all unbacked AND partly contradict the locked auto-refund decision. Build only after resolving the manual-vs-auto policy.

### activity — 🔴 Blocked (effort L)
- **Existing usable:** —
- **NEW** [new audit-log service (or cross-service aggregator)] `adminListActivity` — GET /admin/activity?category=&search=&limit=&offset= returning {occurred_at, category/service, actor (name|system), action, entity_type, entity_id, description, ip_address, payload} newest-first — no cross-service activity/audit-log endpoint or store exists in v2
- **Why:** v2 has NO cross-service activity/audit-log endpoint. The only timestamped admin-readable stream today is reviews (already on /reviews). PDPA access_audit rows ARE written (e.g. adminListGuardProfiles writes a §30 access_audit row) but there is no read API and they capture data-access, not the business-action feed (approved/refund/created/checkin) the screen needs with actor name, IP, and per-action payload. Requires a dedicated audit-event store (NATS event sink) + admin read endpoint. Data does not exist as a queryable feed = fully-blocked.

### automation — 🔴 Blocked (effort L)
- **Existing usable:** —
- **NEW** [new automation/rules service] `listRules / createRule / toggleRule` — GET /admin/rules, POST /admin/rules {trigger, condition, action}, PUT /admin/rules/{id}/enabled {enabled} — no automation/rules/trigger CRUD endpoint or rule-storage table exists anywhere
- **Why:** Verified: no automation/rules/trigger CRUD endpoint (grep hits are substring noise like 'triggers force-revoke-all'). The trigger taxonomy maps conceptually to existing NATS events (booking.cancelled, missed check-in, rating.submitted <=2 stars, document expiry) and actions to existing services (notification send, payment fee/refund, profile flag), but there is NO rule engine, NO rule-storage table, NO rule list/create/toggle endpoint. Forward-looking design. Data/engine does not exist = fully-blocked; ship as API-gap page documenting the conceptual mapping to NATS events.

### expiring — 🔴 Blocked (effort L)
- **Existing usable:** —
- **NEW** [profile] `adminListExpiringDocuments` — GET /admin/documents/expiring?window=expired|7|30|90 returning per-document rows (guard_id, guard_name, document_type, expiry_date, last_reminded_at) — REQUIRES new schema columns: the profile document model has only nullable document-KEY columns and NO expiry_date or last_reminded_at fields
- **NEW** [notification] `sendRenewalReminder` — reuse sendNotification (admin-only) or a bulk variant to nudge guards to re-upload
- **Why:** Verified against profile.yaml: the schema 'carries nullable document-key columns (id card, security license, training cert, criminal check, driver license, passbook photo)' but document UPLOAD itself is a deferred follow-up and there is NO expiry_date and NO last_reminded_at field anywhere. So the entire screen's data (expiry dates, the 4 window buckets/KPIs which are derived from expiry_date, last-reminded timestamps) does not exist in any service. Needs schema migration + a new admin documents-by-expiry endpoint + reminder tracking. The reminder action could reuse sendNotification but there's nothing to remind ABOUT until the expiry fields exist. Data does not exist anywhere = fully-blocked.

### recruit — 🔴 Blocked (effort L)
- **Existing usable:** `adminListGuardProfiles`, `adminApproveGuard`, `adminRejectGuard`
- **NEW** [new recruitment service (or profile extension)] `listCandidates / createCandidate / moveCandidateStage` — GET /admin/candidates (5-stage pipeline: sourcing/screened/docs-verified/approved/onboarded), POST /admin/candidates, PUT /admin/candidates/{id}/stage — no recruitment/candidate/pipeline endpoint exists anywhere (grep recruit|candidate|applicant|pipeline = empty)
- **Why:** Verified: grep of contracts/openapi for recruit|candidate|applicant|pipeline is empty. The closest real surface is the guard-onboarding flow: adminListGuardProfiles (with ?approval_status filter + years_of_experience + approval_status fields, confirmed) + adminApproveGuard + adminRejectGuard, backed by approval_status enum [pending, approved, rejected]. That covers ONLY the design's last two columns (Approved / Onboarded~=approved) and the approve/reject actions. It has NO concept of Sourcing/Screened/Docs-verified stages, source attribution, interview status, background-check tracking, or 'Add candidate' create, and no drag-to-move stage mutation. The 5-stage kanban is entirely unbacked = fully-blocked (though a degraded approve/reject-only view could ship as an API-gap page reusing the 3 existing endpoints).

### reports — 🔴 Blocked (effort L)
- **Existing usable:** —
- **NEW** [payment] `reportRevenueTrend` — GET /admin/reports/revenue?from=&to= returning a daily/period revenue+booking-count time series WITH prior-period comparison for MoM%
- **NEW** [booking] `reportBookingsByService` — GET /admin/reports/bookings-by-service?from=&to= returning per-service-type counts/percentages — NOTE: Booking has no service_type field today, so this also needs a service-type dimension added
- **NEW** [presence/booking] `reportGuardUtilization` — GET /admin/reports/guard-utilization?from=&to= returning a [day-of-week x 2-hour bucket] guard-hours matrix
- **NEW** [booking/identity] `reportRetentionCohort` — GET /admin/reports/retention?from=&to= returning % of a cohort still booking at week N
- **Why:** Pure analytics dashboard — 4 computed rollups, no row-level data. NONE of the existing list endpoints return aggregates, and each metric crosses service boundaries (payment for revenue, booking for counts/service-mix, presence+booking for utilization hours, booking+identity for retention cohorts). Additionally the 'bookings by service' breakdown assumes a service_type dimension the Booking model does not expose. All four need brand-new analytics/reporting endpoints. No aggregate surface exists = fully-blocked.
