# NATS subject-permission ACL (per-service least privilege)

> Source of truth for the broker authorization in `infra/docker/nats.conf` (compose) and
> `infra/k8s/base/nats.yaml` (k8s). Derived from the real publish/subscribe call sites in
> `services/*/src/events/` + `services/api-gateway/src/ws.rs`. Enforced + regression-tested by
> `packages/shared-events/tests/nats_acl.rs` (gated). Keep this table and `nats.conf` in sync.

## Threat model

Before this slice NATS had **no server-side auth** — any container that reached the network
could publish or subscribe to **any** subject. The signed envelope (`EVENT_SIGNING_SECRET`,
HMAC-SHA256) stops a *forged payload* from being applied by a consumer, but it does **not** stop
an unauthorized publish/subscribe (a compromised container could still emit a validly-signed
event for a context it has no business in, since the signing key is shared, or subscribe to and
exfiltrate every event). Per-service users with subject permissions close that: a compromised
**booking** container can only publish `pguard.events.booking.*` — it cannot emit a
`payment.completed` or a `user.compromised`, and consumer-only services can publish nothing.

## Data-plane matrix (the meaningful boundary)

Each producer publishes ONLY its bounded-context subjects. Consumer-only services publish no
event at all. (Subjects resolved from `packages/shared-events/src/lib.rs::topics`.)

| Service        | NATS user      | Publishes (data)              | Consumes (data)                         | Notes |
|----------------|----------------|-------------------------------|-----------------------------------------|-------|
| booking        | `booking`      | `pguard.events.booking.>`     | `pguard.events.payment.completed`       | outbox relay + JS consumer (PRE-PAY gate: stamps `paid_at` → un-gates en_route) |
| payment        | `payment`      | `pguard.events.payment.>`     | `pguard.events.booking.completed`       | also a JS consumer |
| rating         | `rating`       | `pguard.events.rating.>`      | —                                       | outbox relay |
| calling        | `calling`      | `pguard.events.calling.>`     | —                                       | outbox relay |
| chat           | `chat`         | `pguard.events.chat.>`        | —                                       | outbox relay |
| profile        | `profile`      | `pguard.events.user.>`        | —                                       | produces `user.approved` (approval→login) |
| identity       | `identity`     | — (none)                      | `user.approved`, `user.compromised`     | **consumer-only** in production — refresh-reuse → DB `revoke_family`, force-revoke → Redis trv (neither is NATS). Widen to `pguard.events.user.>` only if a real NATS `user.compromised` producer is added. |
| notification   | `notification` | — (none)                      | `pguard.events.>` (durable)             | **consumer-only — cannot publish** |
| presence       | `presence`     | — (none)                      | `pguard.events.booking.>` (durable)     | **consumer-only**; GPS fan-out is Redis, not NATS |
| api-gateway    | `gateway`      | — (none)                      | `pguard.events.booking.*` (CORE sub)    | status-WS hub; non-JetStream subscribe |
| otp            | (no NATS)      | —                             | —                                       | no events module |
| mediasoup      | (no NATS)      | —                             | —                                       | Node SFU |
| monitoring     | `monitoring`   | `$SYS.REQ.>`, `$JS.API.INFO`  | `$SYS.>`, `_INBOX.>`                     | nats-surveyor / exporter (read-only system + JS info) |

## Control-plane (JetStream)

There is exactly **one** stream, `PGUARD_EVENTS` (subjects `pguard.events.>`), created
idempotently via `get_or_create_stream` by every JS client. JS clients (every producer +
durable consumer) share the JetStream control subjects:

- **publish**: `$JS.API.>` (stream/consumer create + info, pull-`next`), `$JS.ACK.>` (message ack)
- **subscribe**: `_INBOX.>` (request replies + pull-consumer delivery)

The api-gateway uses a **core** (non-JS) subscribe, so it instead gets `subscribe` on
`pguard.events.booking.>` and publishes nothing.

### Residual + follow-up

`$JS.API.>` is granted broadly (not scoped per-stream). With a single stream the residual is
bounded: a compromised JS client could disrupt the shared `PGUARD_EVENTS` stream (a
control-plane integrity/DoS concern) but **cannot forge cross-context data events** (the
data-publish allowlist + signed envelopes prevent that). Scoping to
`$JS.API.*.PGUARD_EVENTS.>` is a deliberate follow-up — kept broad here so a permission typo
can't break JetStream and take the bus (and staging) down. Tracked in PENTEST-CHECKLIST.md.

## Credentials + rollout

- One **distinct** password per user (`NATS_<SERVICE>_PASSWORD`), `${VAR:?}` like every other
  secret (a shared password would let a compromised container impersonate a more-privileged
  user). See `infra/.env.staging.example`; rotate per `docs/SECRET-ROTATION.md`.
- **Zero-downtime rollout**: enabling auth on the broker AND distributing per-service creds must
  land in **one** deploy (`git pull` → recreate `nats` with the config + recreate every service
  with its `NATS_USER`/`NATS_PASSWORD`). There is a sub-second window during the rolling
  recreate where a not-yet-recreated service connects anonymously and is rejected by the
  now-auth broker; the services' relay/consumer loops **retry on connect failure** (they never
  crash), so they self-heal the moment their new creds land. Do not enable broker auth in a
  separate deploy from the service creds.
- **Backward-compatible**: `shared_events::connect` connects anonymously when
  `NATS_USER`/`NATS_PASSWORD` are unset, so local dev (`docker compose -f docker-compose.yml`)
  and the CI integration broker (no auth) keep working unchanged.
