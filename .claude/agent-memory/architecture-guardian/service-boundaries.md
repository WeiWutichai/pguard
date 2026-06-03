---
name: Service Boundaries
description: What each service owns + what crosses boundaries via events vs API
type: project
---

# Service boundaries (post Phase 3)

## Ownership (write authority)

| Service | Schema | Primary entities |
|---|---|---|
| identity | `identity` | users, sessions, refresh_tokens, JWT issuance |
| profile | `profile` | guard_profiles, customer_profiles, documents |
| otp | `otp` | otp_codes, phone_verifications |
| booking (assignment) | `booking_assignments` | guard_requests, assignments, available_guards view |
| payment | `booking_payments` | payments, refunds, receipts, proration ledger |
| rating | `reviews` | guard_reviews, visibility moderation |
| calling | `calling` | calls, call signaling state |
| presence | `presence` | guard_locations, location_history |
| notification | `notification` | notifications, devices (FCM tokens) |
| chat | `chat` | conversations, messages, attachments, read_receipts |
| mediasoup | (Redis state) | active call rooms |

## Allowed cross-service reads (via API + service-JWT)

| Reader | Reads from | Endpoint | Why |
|---|---|---|---|
| api-gateway | identity | `GET /internal/identity/users/{id}` | RBAC at edge |
| payment | booking (assignment) | `GET /internal/booking/assignments/{id}/billing-context` | started_at, booked_hours for proration |
| notification | profile | `GET /internal/profile/users/{id}/notification-prefs` | locale, device tokens |
| presence | booking | `GET /internal/booking/assignments/active?guard_id={id}` | scope GPS sharing |
| (any) | identity | `POST /internal/identity/jwt/verify` | service-JWT, rarely needed at runtime |

All `/internal/*` require service-JWT (`SERVICE_JWT_SECRET`).

## Events (subscribe instead of read)

Most cross-service state propagation = events. Subscribers don't query producers.

| Producer | Event | Subscribers |
|---|---|---|
| booking | `pguard.events.booking.job_accepted` | notification, chat (init conversation), presence (start tracking) |
| booking | `.guard_en_route`, `.arrived`, `.completed`, `.cancelled` | notification (push), chat (status messages) |
| payment | `pguard.events.payment.completed` | notification (receipt) |
| payment | `pguard.events.payment.refund_processed` | notification (refund email) |
| rating | `pguard.events.rating.submitted` | notification (guard receives rating), booking (update guard avg) |
| calling | `pguard.events.calling.initiated`, `.accepted`, `.rejected`, `.ended` | chat (system message), notification |
| chat | `pguard.events.chat.message_sent` | notification (push if recipient offline) |
| identity | `pguard.events.user.compromised` | all services (clear caches, force-revoke) |

## Forbidden patterns

- ❌ Reading another service's tables directly via SQL
- ❌ Writing to another service's tables directly
- ❌ Cross-schema FK in new migrations
- ❌ A service publishing events outside its bounded context (booking can't publish `pguard.events.payment.*`)
- ❌ Subscriber writing to producer's schema after handling event (loop)
