# Staging deployment — VPS artifacts + runbook (replace v1 · manual deploy · nginx+certbot) — work spec

> For Claude Code. Produce everything needed to run pguard v2 on the existing VPS as **staging**,
> pulling images from ghcr. Decisions (locked by the user): **replace v1** (stop guard-dispatch,
> give v2 the full box) · **manual deploy** (CI builds+pushes images; a human SSHes to pull+up) ·
> **nginx + certbot** TLS. The VPS-side steps (SSH, secrets, DNS, certbot) are the **user's** to run
> — this slice writes the artifacts + a precise runbook, not live VPS changes. Branch off freshly
> synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull
git worktree add ../pguard-staging -b feat/staging-deploy main
cd ../pguard-staging
```

## VPS facts (from CLAUDE.md, verify)
- Host `srv1569870` · tailnet `100.67.139.123` · public domain `pguard.innoveraappcenter.com` · SSH only via Tailscale (port 22 closed publicly) · ghcr packages **private** · owner `WeiWutichai` (downcase for ghcr paths).

## Scope

### A. `infra/docker/docker-compose.staging.yml` — override on top of prod
Used as `docker compose -f docker-compose.prod.yml -f docker-compose.staging.yml`. For each of the **14 custom images** (postgres-primary, api-gateway, identity, profile, otp, notification, booking, payment, rating, calling, presence, chat, mediasoup, web-admin): override `image:` → `ghcr.io/${IMAGE_PREFIX}/<svc>:${IMAGE_TAG:-latest}` so the stack **pulls from ghcr** (no build on the VPS). `IMAGE_PREFIX` = `weiwutichai/pguard` (lowercase), `IMAGE_TAG` = git sha or `latest` — `${VAR:?}`-style where it must be explicit.
- **Add `nginx`** service: publishes 80/443, TLS-terminates, proxies `/` → `api-gateway:3000` (and `/p-guard-app` or `/` → `web-admin:3000` per the routing you choose), mounts certs + `nginx.staging.conf` + a certbot webroot. nginx is the **only** host-exposed service — set the gateway's `ports: []` in the override (everything else stays `expose`).
- Enable the **`ui` profile** (web-admin) since slice-2 made web-admin build; bring it into the staging stack.
- Set `MEDIASOUP_ANNOUNCED_IP` to the VPS public IP (env). Keep observability (Grafana/Tempo/Loki/Prometheus) internal-only (behind nginx auth or not exposed).

### B. `infra/docker/nginx.staging.conf`
TLS server block(s) for `pguard.innoveraappcenter.com`: certbot cert paths, HTTP→HTTPS redirect + ACME `/.well-known/acme-challenge/` webroot, proxy to `api-gateway:3000` (API + WS upgrade headers for `/v1/ws/*`) and web-admin. Carry the security headers + per-path `client_max_body_size` (uploads) + rate-limit zones (auth/otp tighter) the gateway expects — mirror the v1 nginx.prod.conf hardening. WebSocket `Upgrade`/`Connection` headers on the WS routes.

### C. `infra/.env.staging.example`
All required secrets/vars with placeholders + comments: `POSTGRES_PASSWORD · REPLICATION_PASSWORD · JWT_SECRET · SERVICE_JWT_SECRET · EVENT_SIGNING_SECRET · MINIO_ROOT_USER/PASSWORD · GRAFANA_ADMIN_PASSWORD · INET_SMS_* (or SMS_DISABLED=true for staging) · MEDIASOUP_ANNOUNCED_IP · CORS_ALLOWED_ORIGINS=https://pguard.innoveraappcenter.com · IMAGE_PREFIX · IMAGE_TAG · REGISTRY=ghcr.io`. Gitignored real file.

### D. Wire CI image push (deploy.yml)
Confirm `deploy.yml`'s build-push matrix pushes all 14 images to ghcr on push to main (it should already). Keep the **deploy job `if: false`** (manual). Document that staging pulls these tags. If anything blocks the push (perms/casing), fix it.

### E. `docs/STAGING-SETUP.md` — the VPS runbook (the user runs this)
Precise, ordered, copy-paste steps:
1. **Stop v1** — `cd /root/guard-dispatch && docker compose down` (keep its volumes/dir as reference; don't delete).
2. **Get pguard** — clone/checkout pguard at `/root/pguard` (or pull).
3. **DNS** — confirm `pguard.innoveraappcenter.com` → VPS public IP.
4. **ghcr login** (private packages, manual) — `docker login ghcr.io` with a PAT (`read:packages`).
5. **Secrets** — copy `.env.staging.example` → `.env`, fill real values (`openssl rand -hex 48` for the ≥64-char secrets; `SMS_DISABLED=true` unless testing OTP).
6. **certbot** — issue the cert (webroot or standalone) for the domain; note renewal.
7. **Pull + migrate + up** — `export IMAGE_PREFIX/IMAGE_TAG/REGISTRY` → `docker compose -f docker-compose.prod.yml -f docker-compose.staging.yml pull` → run the migrator (`tooling/scripts/migrate.sh`) → `up -d` (excluding mediasoup if the 41641/Tailscale RTC-port conflict bites — note the workaround).
8. **Smoke test** — `curl https://pguard.innoveraappcenter.com/v1/otp/challenge`, web-admin loads, `pg_stat_replication` streaming.
9. **Redeploy loop** — pull new tag + up -d + migrate; rollback by pinning a prior `IMAGE_TAG`.
Call out the gotchas we already hit: nats:2-alpine (done), replica bootstrap baked into image (done), pgbouncer 6432 + prepared-statements (done), mediasoup RTC-port vs Tailscale 41641.

## Definition of Done
- `docker compose -f docker-compose.prod.yml -f docker-compose.staging.yml config` validates (with example env) → resolves ghcr image refs, nginx added, gateway not host-published, web-admin in.
- nginx.staging.conf valid (`nginx -t` in a throwaway container) with TLS + WS + security headers + rate zones.
- `.env.staging.example` complete; deploy.yml confirmed pushing 14 images (deploy job stays if:false).
- `STAGING-SETUP.md` is a runnable, ordered runbook with the real host/domain + the known gotchas.
- Update `PROGRESS.md` (tick staging-deploy + Completed-log row) · run the review agents (security-reviewer on TLS/secrets/exposure + code + architecture) · own PR off main · **don't merge**.

## Reference (read-only)
- Adapt: `../guard-dispatch/{docker-compose.staging.yml, nginx/nginx.prod.conf}` (v1 staging + TLS patterns — the casing/`${IMAGE_PREFIX:?}`/Tailscale notes are in CLAUDE.md). Base: `infra/docker/docker-compose.prod.yml` (service list + ports + the harness fixes). CI: `.github/workflows/deploy.yml`. Migrator: `tooling/scripts/migrate.sh`.
