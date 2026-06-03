---
name: v1 Anti-patterns
description: Patterns from guard-dispatch v1 that must not regress in pguard v2
type: project
---

# v1 anti-patterns to block in v2

## Backend

### Cross-schema direct writes (v1 booking → notification/chat)
Pattern: `tokio::spawn(async move { sqlx::query("INSERT INTO notification.notification_logs ...").execute(&db).await })`
Where to find in v1: `services/booking/src/service.rs` line 92-152 (`spawn_notification` helper), called from 10 sites
Replacement: emit NATS event, let notification service subscribe and write to its own schema

### Direct INSERT into chat.messages from booking (BUG-038)
v1 `services/booking/src/service.rs:5037, 5089` wrote "call ended/rejected" records into chat schema
Replacement: chat service exposes `POST /chat/system-messages` (or subscribe `pguard.events.calling.ended`)

### service.rs god-file
v1 `booking/service.rs` = 5,400 LOC, `auth/service.rs` = 3,400 LOC. Multiple unrelated state machines in one file.
v2 rule: per-domain file (proration.rs, refund.rs, receipt.rs, etc.) in `domain/`

### `tokio::spawn` fire-and-forget for state-changing work
Loses the operation on crash. Use transactional outbox + relay.

## Flutter

### Provider god-providers
v1 AuthProvider = 888 LOC, did: registration orchestration, profile fetch, role switching, token lifecycle
v2 rule: feature-scoped Riverpod providers, no god-providers

### Countdown math in screen state
v1 active_job_screen.dart had `_calcRemainingFromStartedAt()`, `_checkHourBoundary()` (~40 LOC of business logic) coupled to widget state
v2 rule: `CountdownController` in `core/controllers/` — testable without widget

### IndexedStack stale state (BUG-022)
v1 dashboard kept all tab children mounted, `initState` fires once. Backend changes while user on other tab → cached state stale on tab switch.
v2 rule: route tab switch through method that refreshes provider — or use Riverpod's `ref.invalidate(provider)` on switch

### Timer.periodic everywhere
v1 customer_tracking 2 timers, customer_active_job 1 timer (no WS!), waiting_for_guard 1 timer, active_job 2 timers + WS. Up to 13 concurrent in worst case. BUG cluster.
v2 rule: WebSocket subscription via AssignmentSocketService; polling only as 30s safety-net fallback

### Provider depending on AuthProvider.phone (nullable)
v1 BookingProvider would call methods assuming `auth.phone != null` — fragile
v2 rule: dependencies via Riverpod's `ref.watch(authPhoneProvider).requireValue` or AsyncValue handling
