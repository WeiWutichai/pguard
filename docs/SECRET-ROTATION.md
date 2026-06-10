# Secret rotation runbook (staging / VPS)

> Per-secret rotation steps for the pguard v2 stack. Closes v1-audit risk **#14 (no secret
> rotation)** with an actual procedure. Every secret is externalized via `${VAR:?}` (no
> in-image defaults), so rotation = change the value in `infra/.env.staging` and recreate the
> consumers — no rebuild.
>
> **Conventions used below** (match `docs/STAGING-SETUP.md`):
> - VPS checkout: `/root/pguard` · compose project: `pguard-prod`
> - Compose invocation (always both files + the gitignored env):
>   ```bash
>   cd /root/pguard
>   COMPOSE="docker compose -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.staging.yml --env-file infra/.env.staging"
>   ```
> - Generators: `openssl rand -hex 48` (JWT/service-JWT/event-signing/TURN, ≥64 chars),
>   `openssl rand -hex 24` (DB / MinIO passwords) — **ยกเว้น NATS: ใช้ `np$(openssl rand -hex 23)`** (ค่าใน nats.conf ที่ขึ้นต้นด้วยตัวเลขทำ parser พัง → broker boot fail; เจอจริง 2026-06-10).
> - Edit secrets in `infra/.env.staging` (NEVER committed — it is gitignored; the tracked
>   template is `infra/.env.staging.example`).

## ⚠️ Capability matrix — what each rotation costs

The code validates JWTs / signatures against a **single** secret (no dual-secret /
overlap-window verification is implemented). So a key rotation invalidates everything signed
with the old key the instant services pick up the new one. Plan downtime/impact accordingly.

| Secret | Verification | Rotation impact | Mitigation |
|--------|--------------|-----------------|------------|
| `JWT_SECRET` | single (`JwtConfig`, `config.rs:185`) | **All** access + refresh tokens invalid → every user re-logs-in | access tokens are short-lived; do it in a low-traffic window |
| `SERVICE_JWT_SECRET` | single (`config.rs:207`) | brief inter-service `/internal` auth failures during the rolling recreate | service-JWTs are short-TTL (~60s), minted per-request → self-heals in seconds |
| `EVENT_SIGNING_SECRET` | single (`OnceLock`, `sig.rs`) | events published with the OLD key are rejected by consumers on the NEW key (dropped) | rotate at low traffic; let the outbox drain first (below) |
| `NATS_<svc>_PASSWORD` | broker authz | the one service whose password changed reconnects | recreate that service + nats together; relay/consumer loops retry |
| `POSTGRES_PASSWORD` | postgres role | DB clients reconnect | rotate role + every `DATABASE_URL` consumer in one deploy |
| `MINIO_ROOT_USER/PASSWORD` | MinIO | S3 clients (booking/chat) re-auth | rotate MinIO creds + S3_* envs together |
| `TURN_SECRET` | coturn HMAC | in-flight TURN creds expire early; new calls fine | short TURN cred TTL already |

> **Follow-up (not yet implemented):** dual-secret verification windows (`JWT_SECRET_PREVIOUS`,
> `EVENT_SIGNING_SECRET_PREVIOUS`) for zero-impact rotation. Until then the impacts above apply.

---

## JWT_SECRET (user access/refresh tokens)

Single-secret → rotation forces a system-wide re-login. `token_revocation_version` (trv) is for
TARGETED force-revoke-all of one user (compromise), NOT for secret rotation — it does not give a
grace window here.

```bash
cd /root/pguard
NEW=$(openssl rand -hex 48)
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${NEW}|" infra/.env.staging
# Recreate every Rust service (all validate JWT_SECRET at startup) + the gateway:
$COMPOSE up -d api-gateway identity profile otp notification booking payment rating calling presence chat
# Verify: a NEW login works; an OLD access token now 401s at the edge.
curl -fsS https://pguard.innoveraappcenter.com/healthz   # gateway healthy after restart
```

Users are prompted to re-authenticate (the app routes to lock/login on the first 401 with no
working refresh). Announce the window if it matters.

## SERVICE_JWT_SECRET (internal service-to-service)

```bash
cd /root/pguard
NEW=$(openssl rand -hex 48)
sed -i "s|^SERVICE_JWT_SECRET=.*|SERVICE_JWT_SECRET=${NEW}|" infra/.env.staging
# Recreate every service that MINTS or VERIFIES a service-JWT (payment→booking, booking→profile/
# rating, identity internal, etc.) — recreate the whole rust fleet to be safe, in one shot:
$COMPOSE up -d api-gateway identity profile otp notification booking payment rating calling presence chat
```

Low impact: service-JWTs are ~60s TTL and minted per call, so any request that fails mid-rotate
retries successfully once both caller and callee are on the new secret (sub-second window).

## EVENT_SIGNING_SECRET (signed NATS envelopes)

Single key. Events ALREADY in the `PGUARD_EVENTS` stream signed with the old key will be DROPPED
by consumers running the new key (signature mismatch → ack-without-apply). Drain first:

```bash
cd /root/pguard
# 1. Quiesce: confirm the outbox tables are empty (all events published) before rotating.
$COMPOSE exec postgres psql -U pguard -d pguard -tAc \
  "select coalesce(sum(c),0) from (select count(*) c from booking.outbox where published_at is null
     union all select count(*) from payment.outbox where published_at is null
     union all select count(*) from chat.outbox where published_at is null
     union all select count(*) from profile.outbox where published_at is null) s;"   # expect 0
# 2. (Optional) purge the JetStream stream so no old-key events linger for a slow consumer:
$COMPOSE exec nats nats --user monitoring --password "$NATS_MONITORING_PASSWORD" \
  stream purge PGUARD_EVENTS -f   # or recreate nats (ephemeral store on compose)
# 3. Rotate + recreate every publisher AND consumer:
NEW=$(openssl rand -hex 48)
sed -i "s|^EVENT_SIGNING_SECRET=.*|EVENT_SIGNING_SECRET=${NEW}|" infra/.env.staging
$COMPOSE up -d identity profile notification booking payment rating calling presence chat
```

Do it in a low-traffic window. Any event produced in the brief recreate gap is retried by the
outbox relay (at-least-once) once the producer is back on the new key.

## NATS per-service passwords (subject-ACL creds)

Each service has its OWN `NATS_<SVC>_PASSWORD` (see `infra/docker/nats.conf` +
`contracts/asyncapi/nats-acl.md`). The broker reads them from its env; each service reads its own
as `NATS_PASSWORD`. To rotate ONE service's NATS password (e.g. booking):

```bash
cd /root/pguard
NEW=$(openssl rand -hex 24)
sed -i "s|^NATS_BOOKING_PASSWORD=.*|NATS_BOOKING_PASSWORD=${NEW}|" infra/.env.staging
# Recreate the broker (re-reads the user table) AND that service (gets the new NATS_PASSWORD),
# together — the order is irrelevant because the service's relay/consumer loop retries on a
# rejected connect until both are aligned (seconds).
$COMPOSE up -d nats booking
```

To rotate ALL NATS passwords at once: regenerate every `NATS_*_PASSWORD`, then
`$COMPOSE up -d nats api-gateway identity profile notification booking payment rating calling presence chat`.

## POSTGRES_PASSWORD

```bash
cd /root/pguard
NEW=$(openssl rand -hex 24)
# 1. Change the role password IN the DB first:
$COMPOSE exec postgres psql -U pguard -d pguard -c "ALTER ROLE pguard WITH PASSWORD '${NEW}';"
# 2. Update every consumer var (the URLs embed the password by design):
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW}|" infra/.env.staging
# (DATABASE_URL/DATABASE_READ_URL/pgbouncer userlist also embed it — update those too if your
#  .env builds them literally; the compose x-db-env derives them from POSTGRES_PASSWORD.)
# 3. Recreate pgbouncer + every DB-backed service:
$COMPOSE up -d pgbouncer identity profile otp notification booking payment rating calling presence chat
```

## MinIO (MINIO_ROOT_USER / MINIO_ROOT_PASSWORD) + TURN_SECRET

```bash
# MinIO: rotate root creds, then recreate minio + the S3 clients (booking, chat). S3_ACCESS_KEY/
# S3_SECRET_KEY map to MINIO_ROOT_* in compose, so updating MINIO_ROOT_* covers both.
sed -i "s|^MINIO_ROOT_PASSWORD=.*|MINIO_ROOT_PASSWORD=$(openssl rand -hex 24)|" infra/.env.staging
$COMPOSE up -d minio booking chat

# TURN: rotate the coturn static-auth-secret + the calling service (which mints creds from it).
sed -i "s|^TURN_SECRET=.*|TURN_SECRET=$(openssl rand -hex 48)|" infra/.env.staging
$COMPOSE up -d coturn calling
```

---

## After any rotation

1. `git -C /root/pguard status` → `infra/.env.staging` must remain **untracked** (gitignored).
2. Smoke: `curl -fsS https://pguard.innoveraappcenter.com/healthz` (gateway) + one real flow
   (login → book) per `docs/STAGING-SETUP.md` §smoke.
3. Record the rotation date in your ops log; recommended cadence: **quarterly**, or immediately
   on suspected exposure.
