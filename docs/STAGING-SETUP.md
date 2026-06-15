# pguard v2 — Staging deploy runbook (VPS)

> **Audience:** the operator running the deploy by hand on the existing VPS.
> **Model:** CI builds + pushes images to ghcr (`.github/workflows/deploy.yml`); a human
> SSHes in to `pull` + `up`. **No automated deploy.** This slice replaces v1 on the box.
>
> **Artifacts this runbook drives** (all committed in the repo):
> - `infra/docker/docker-compose.staging.yml` — override on `docker-compose.prod.yml` (ghcr pulls + nginx + web-admin)
> - `infra/docker/nginx.staging.conf` — TLS edge / single ingress
> - `infra/.env.staging.example` — fill → `infra/.env.staging` (gitignored)
> - `tooling/scripts/migrate.sh` — one-shot migrator

---

## 0. Facts & prerequisites

| Thing | Value |
|---|---|
| Host | `srv1569870` |
| Tailnet IP (SSH) | `100.67.139.123` — **SSH only over Tailscale; public port 22 is closed** |
| Public domain | `pguard.innoveraappcenter.com` |
| ghcr owner | `WeiWutichai` → image paths use the **lowercase** `weiwutichai/pguard` |
| ghcr packages | **private** → a `docker login ghcr.io` with a PAT is required to pull |
| Deploy dir (suggested) | `/root/pguard` |

On the VPS you need: Docker Engine + the Compose v2 plugin (`docker compose version`), `git`,
`openssl`, and the Tailscale session for SSH. Everything below runs **as the deploy user on the
VPS**, from the repo root, unless noted.

> Replace the e-mail/IP placeholders (`ops@…`, the public IP) with the real values.

---

## 1. Stop v1 (free the box + ports 80/443)

```bash
cd /root/guard-dispatch
docker compose down                 # stop containers; KEEP volumes + the directory as reference
docker compose ps                   # confirm nothing is left running
```

Do **not** delete `/root/guard-dispatch` or its volumes — it stays as the read-only v1 reference.
Stopping it frees host ports **80/443** (and any others) for the v2 nginx.

---

## 2. Get pguard onto the VPS

```bash
# first time:
git clone https://github.com/WeiWutichai/pguard.git /root/pguard
cd /root/pguard

# subsequently:
cd /root/pguard && git fetch origin && git checkout main && git pull
```

You only need the repo for the compose files, `nginx.staging.conf`, `migrate.sh`, and the
migrations — **images are pulled from ghcr, never built here.**

---

## 3. DNS

Confirm the domain points at the VPS **public** IP (the public IP, *not* the Tailscale IP):

```bash
dig +short pguard.innoveraappcenter.com      # → must equal the VPS public IP
```

If it doesn't, fix the A/AAAA record at the DNS provider and wait for propagation **before**
issuing the TLS cert (Let's Encrypt http-01 validates over the public IP on port 80).

---

## 4. Log in to ghcr (private packages)

Create a GitHub PAT with **`read:packages`** scope, then:

```bash
echo "$GHCR_PAT" | docker login ghcr.io -u WeiWutichai --password-stdin
```

A successful login writes `~/.docker/config.json`; the later `pull` uses it.

---

## 5. Secrets → `infra/.env.staging`

```bash
cp infra/.env.staging.example infra/.env.staging
# generate strong, UNIQUE secrets:
openssl rand -hex 48        # JWT_SECRET
openssl rand -hex 48        # SERVICE_JWT_SECRET
openssl rand -hex 48        # EVENT_SIGNING_SECRET   (dedicated — never reuse the JWT one)
openssl rand -base64 24     # POSTGRES_PASSWORD / REPLICATION_PASSWORD / MINIO_* / GRAFANA_*
$EDITOR infra/.env.staging  # paste them in; set MEDIASOUP_ANNOUNCED_IP=<VPS public IP>
```

Required values to fill (the compose fails fast if any are empty):
`POSTGRES_PASSWORD`, `REPLICATION_PASSWORD`, `JWT_SECRET`, `SERVICE_JWT_SECRET`,
`EVENT_SIGNING_SECRET`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`,
`MEDIASOUP_ANNOUNCED_IP` (the **public** IP), and `CORS_ALLOWED_ORIGINS`
(already set to `https://pguard.innoveraappcenter.com`).

- **SMS stays OFF by default** (`SMS_DISABLED` defaults to `true` in the staging compose). The
  `INET_SMS_*` placeholders only need to be non-empty. The otp gate is **value-aware**: only a
  truthy value (`true/1/yes/on/y`) disables SMS; `false`/`0`/empty/**unset** ENABLE it. To actually
  send OTP SMS, set `SMS_DISABLED=false` in `.env.staging` and put real INET creds there. Do **not**
  delete the `SMS_DISABLED` line from `docker-compose.staging.yml` — without it the service runs
  with SMS ON.
- `infra/.env.staging` is **gitignored** (matches `.env`/`.env.*.local`). Never commit it.

Then export the image coordinates + secrets for this shell:

```bash
set -a; source infra/.env.staging; set +a
export REGISTRY=ghcr.io
export IMAGE_PREFIX=weiwutichai/pguard
export IMAGE_TAG=latest          # or a specific git SHA — see §9 for pinning/rollback
```

Quick sanity check (resolves image refs + interpolates every `${VAR:?}`):

```bash
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml config -q && echo OK
```

---

## 6. Issue the TLS certificate (certbot)

nginx needs the cert present at start, so issue it **before** the stack is up (v1 is already
stopped, so port 80 is free for standalone validation):

```bash
mkdir -p /var/www/certbot
docker run --rm -p 80:80 \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/www/certbot:/var/www/certbot \
  certbot/certbot certonly --standalone \
  -d pguard.innoveraappcenter.com \
  --email ops@innoveraappcenter.com --agree-tos --no-eff-email
```

This writes `/etc/letsencrypt/live/pguard.innoveraappcenter.com/{fullchain,privkey}.pem`, which
`nginx.staging.conf` reads (mounted read-only). **Renewal** later uses the webroot (nginx serves
`/.well-known/acme-challenge/` from `/var/www/certbot`) — see §10.

---

## 7. Pull, bring up, migrate

```bash
# 7a. pull all 14 custom images from ghcr (+ the pinned 3rd-party images)
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml pull

# 7b. start the whole stack (nginx now finds the cert from §6)
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml up -d

# 7c. apply migrations to the PRIMARY (services do NOT auto-migrate; the replica
#     picks the DDL up over WAL). migrate.sh execs into the running `postgres`
#     container of this same compose project.
set -a; source infra/.env.staging; set +a
tooling/scripts/migrate.sh
```

Watch it settle:

```bash
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml ps
# all services healthy; check logs for any one that restarts:
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml logs -f api-gateway nginx
```

> The replica base-backs up from the primary on first boot (`pg_basebackup`, can take a couple of
> minutes — the healthcheck `start_period` is 120s). Services tolerate a replica blip (read pool is
> lazy) and degrade reads to the primary.

---

## 8. Smoke test

```bash
# 8a. gateway through nginx + TLS (public OTP challenge — no auth needed)
curl -fsS https://pguard.innoveraappcenter.com/v1/otp/challenge && echo

# 8b. gateway readiness + nginx liveness
curl -fsS https://pguard.innoveraappcenter.com/healthz && echo
curl -fsS https://pguard.innoveraappcenter.com/health  && echo   # nginx-local "healthy"

# 8c. web-admin loads (expect 200 + HTML)
curl -fsSI https://pguard.innoveraappcenter.com/ | head -n1

# 8d. HTTP→HTTPS redirect works
curl -sI http://pguard.innoveraappcenter.com/ | grep -i location   # → https://…

# 8e. security headers present once (no duplicates)
curl -sI https://pguard.innoveraappcenter.com/v1/otp/challenge | grep -iE 'strict-transport|x-frame|content-security'

# 8f. streaming replication is live (run inside the primary)
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml exec postgres \
  psql -U pguard -d pguard -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
#   → one row, state = streaming
```

If `8a` returns a JSON body and `8f` shows a `streaming` row, the core stack is up.

---

## 9. Redeploy loop (new build) + rollback

CI pushes `:latest` **and** `:<git-sha>` on every push to main (the `:<git-sha>` is the **FULL
40-char** sha, not the short form). **Pin a SHA in staging** so a redeploy is deterministic and
rollback is trivial.

> **One command** (sources `infra/.env.staging`, pulls, ups, migrates, recreates nginx,
> prints status — defaults `IMAGE_TAG` to the full HEAD sha):
> ```bash
> cd /root/pguard && git pull && bash tooling/scripts/deploy-staging.sh
> # rollback to a known-good full sha:
> bash tooling/scripts/deploy-staging.sh <full-git-sha>
> ```
> The manual steps below are the same thing expanded, if you need to run a stage by hand.

```bash
cd /root/pguard && git pull                  # get any compose/nginx/migration changes
set -a; source infra/.env.staging; set +a
export REGISTRY=ghcr.io IMAGE_PREFIX=weiwutichai/pguard
export IMAGE_TAG=<new-git-sha>               # the SHA you want to deploy

docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml pull
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml up -d --remove-orphans
tooling/scripts/migrate.sh                   # apply any new migrations (idempotent)

# nginx caches the upstreams' IPs at start; `up -d` may recreate a backend with a NEW
# IP. Recreate nginx so it re-resolves (otherwise it 502s the changed service):
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml up -d --force-recreate nginx
```

**Rollback** = redeploy a known-good prior SHA (migrations are forward-only — only roll back to a
SHA whose schema matches what's applied):

```bash
export IMAGE_TAG=<previous-good-sha>
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml pull
docker compose -f infra/docker/docker-compose.prod.yml \
               -f infra/docker/docker-compose.staging.yml up -d --force-recreate
```

---

## 10. TLS renewal (set once)

Let's Encrypt certs last 90 days. Renew via webroot (zero downtime — nginx keeps serving):

```bash
# dry-run first
docker run --rm \
  -v /etc/letsencrypt:/etc/letsencrypt \
  -v /var/www/certbot:/var/www/certbot \
  certbot/certbot renew --webroot -w /var/www/certbot --dry-run
```

Add a cron entry (e.g. `crontab -e`) that renews and reloads nginx:

```cron
# `exec -T` (no TTY) — cron has no terminal, so a bare `exec` errors with "input device is not a TTY".
0 3 * * * docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v /var/www/certbot:/var/www/certbot certbot/certbot renew --webroot -w /var/www/certbot --quiet && docker compose -f /root/pguard/infra/docker/docker-compose.prod.yml -f /root/pguard/infra/docker/docker-compose.staging.yml exec -T nginx nginx -s reload
```

---

## Gotchas (things we already hit — don't relearn them)

- **nats image** — must be `nats:2-alpine` (the prod compose already pins it). `nats:latest` /
  wrong tags previously broke JetStream startup. No action needed; just don't "upgrade" it blindly.
- **Postgres replica bootstrap is BAKED into the image** — the `postgres` service pulls the
  custom `ghcr.io/weiwutichai/pguard/postgres-primary` image, which bakes
  `infra/db/primary-replication-init.sh` into `/docker-entrypoint-initdb.d/`. This is deliberate:
  a bind-mounted init script raced/lost its exec bit on Docker Desktop and the replica could never
  base-backup. **Don't** "simplify" it back to a bind mount. (This is why `postgres-primary` is the
  14th image in `deploy.yml`.)
- **pgbouncer** — listens on **6432** (`LISTEN_PORT`), `AUTH_TYPE=scram-sha-256` (postgres:17),
  `POOL_MODE=transaction`, and `MAX_PREPARED_STATEMENTS=256` (so sqlx's named prepared statements
  don't collide under transaction pooling). Already set in the prod compose — if a DB-backed
  service can't connect, check it's hitting `pgbouncer:6432`, not `5432`.
- **mediasoup UDP vs Tailscale 41641** — Tailscale's direct-connection port (UDP **41641**) sits
  inside the prod default media range (40000-49999), and publishing 10k UDP ports also makes
  `up` crawl. `infra/.env.staging.example` therefore defaults the range to **42000-42199**
  (avoids 41641, far fewer ports). If WebRTC media still won't connect or `up` errors on a port
  bind, either narrow further or **bring the stack up without mediasoup** and add it later:
  ```bash
  docker compose -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.staging.yml \
    up -d --scale mediasoup=0
  ```
- **nginx needs the cert at start** — issue the cert (§6) *before* `up -d`, or nginx restart-loops
  on the missing `ssl_certificate`. After issuance it starts clean.
- **Project name stays `pguard-prod`** — the staging override doesn't rename the project, so
  containers are `pguard-prod-*` and `migrate.sh` (default `COMPOSE_FILE` = the prod file) `exec`s
  into the right `postgres`. This is intentional; don't add `name:` to the staging file.

---

## Known limitations (as of `main`)

- **Gateway routing gap — closed.** The api-gateway now routes every service: REST
  `auth · otp · profile · bookings · available-guards · payments · calls · notifications · tokens ·
  admin/guard-profiles · conversations/attachments (chat) · locations + guards/{id}/location·history
  (presence) · guards/{id}/ratings + assignments/{id}/review + admin/reviews (rating)`, the
  booking-status WebSocket (`/v1/ws/bookings/{id}`), and the generic WS proxies `/v1/ws/chat`,
  `/v1/ws/track`, `/v1/ws/call`. Staging picks these up with the next gateway image — **no change to
  `nginx.staging.conf` needed.** (Follow-up: the web-admin e2e env-gated rewrites
  `PGUARD_RATING_URL`/`PGUARD_PRESENCE_URL` in `apps/web-admin/next.config.ts` retired 2026-06-11 (PR #39) — historical note: could be retired once
  the e2e suite is re-verified against the gateway.)
- **Request-body caps on `/v1` (default 1 MiB; 12 MiB on the two upload routes).** The gateway
  buffers request bodies with a hard **1 MiB** cap by default (clean JSON `413`), which is also the
  WS per-frame cap. **Carve-out (closed):** the two multipart upload routes —
  `POST /v1/attachments` (chat image) and `POST /v1/bookings/{id}/progress-reports` (guard check-in
  photo) — get a **12 MiB** cap at both nginx (`location`-scoped `client_max_body_size 12m`) and the
  gateway (`domain::routing::body_cap_for` → `BodyCap::Large`). So a ≤10 MiB image now reaches the
  backend (which re-validates size + magic bytes). Every other route still caps at 1 MiB (nginx
  `client_max_body_size 2m` returns the clean gateway `413` for the rest). Bodies over 12 MiB
  (e.g. large videos) remain rejected through the edge — out of scope.
- **Observability is internal-only.** Grafana/Tempo/Loki/Prometheus are `expose`d on the cluster
  network, never host-published. Reach Grafana via an SSH/Tailscale tunnel
  (`ssh -L 3000:grafana:3000 …` against the host) or add an authenticated nginx location if you
  want it on the domain.
