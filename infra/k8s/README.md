<!-- pguard v2 — infra/k8s -->

# infra/k8s — Kubernetes manifests (base + kustomize overlays)

Kubernetes translation of the stack proven on compose
(`infra/docker/docker-compose.prod.yml` + the staging nginx edge). **The compose files
are the source of truth** — these manifests mirror them service-for-service, env-for-env;
the compose→k8s env diff is the table at the bottom of this file.

> Round 1-B. terraform (Round 2) points at this `base/`. cert-manager + a CI deploy-to-k8s
> job are out of scope (TODOs below).

## Layout

```
infra/k8s/
├── base/                      # env-agnostic manifests, one file per component
│   ├── namespace.yaml · configmap.yaml · secrets.example.yaml (doc-only template)
│   ├── postgres-primary.yaml · postgres-replica.yaml · pgbouncer.yaml
│   ├── nats.yaml · redis.yaml · minio.yaml          # StatefulSets + PVCs (+ pooler)
│   ├── api-gateway.yaml + 10 Rust services          # Deployment + Service each
│   ├── mediasoup.yaml · coturn.yaml                 # hostNetwork (see Network-special)
│   ├── web-admin.yaml
│   ├── otel-collector / tempo / loki / prometheus / grafana   # + embedded config ConfigMaps
│   ├── ingress.yaml           # ingress-nginx: /v1→gateway, /→web-admin, upload carve-out
│   ├── migrate-job.yaml       # one-shot migrator (psql → primary)
│   ├── networkpolicy.yaml     # default-deny + same-ns + edge allow
│   ├── hpa/                   # HPAs (staging-only; NOT in base/kustomization)
│   └── kustomization.yaml
└── overlays/
    ├── dev/                   # replicas:1, no HPA, DUMMY secrets, stock single-DB → kind
    └── staging/              # ghcr images, real host + TLS, HPAs, narrowed RTC, SMS/push off
    # prod/  — TODO: copy staging, point images at the prod registry/tag, real secrets,
    #          tighten resources from the perf baseline, add PodDisruptionBudgets + HA datastores.
```

## Prerequisites

- A cluster (kind/k3s/EKS/GKE/AKS) + `kubectl` and `kustomize` (or `kubectl kustomize`).
- **ingress-nginx** for the Ingress: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml`
  (the Ingress annotations are ingress-nginx-specific).
- **metrics-server** for HPAs (staging): `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
- A default **StorageClass** (the StatefulSets request PVCs). kind/EKS/GKE ship one.
- A CNI that **enforces NetworkPolicy** (Calico/Cilium) if you want east-west isolation —
  kind's default `kindnet` does NOT enforce it (the policies are then inert).

## Deploy order

Apply order is mostly handled for you — kustomize applies everything at once and Kubernetes
reconciles; services crash-loop until the DB is reachable, then recover (their read pool is
lazy). The one MANUAL step is migrations (services do not auto-migrate). The intended sequence:

```bash
# 1) Secrets (see "Secrets" below). dev generates dummies automatically; staging is out-of-band.
# 2) (private images) imagePullSecret — see "Images / ghcr".
# 3) Apply the platform:
kubectl apply -k infra/k8s/overlays/dev        # or overlays/staging
# 4) Wait for the datastores, then run migrations (see "Migrations").
# 5) The Ingress exposes /v1 → gateway and / → web-admin once those pods are Ready.
```

## Secrets

Six logical Secrets carry every `${VAR:?}` from compose (keys enumerated in
`base/secrets.example.yaml` — **a doc template, never applied, never filled-in-and-committed**):
`pguard-app-secrets` · `pguard-db-secrets` · `pguard-s3-secrets` · `pguard-otp-secrets` ·
`pguard-turn-secrets` · `pguard-grafana-secrets`.

- **dev**: generated automatically by `secretGenerator` in `overlays/dev` with **obviously-fake**
  dummy values (safe to commit; JWT/HMAC keys are ≥64 chars as the apps require).
- **staging / prod**: create OUT-OF-BAND from a gitignored env file (the `.env.staging.example`
  pattern) — e.g.

  ```bash
  kubectl -n pguard create secret generic pguard-app-secrets \
    --from-literal=JWT_SECRET="$(openssl rand -hex 48)" \
    --from-literal=SERVICE_JWT_SECRET="$(openssl rand -hex 48)" \
    --from-literal=EVENT_SIGNING_SECRET="$(openssl rand -hex 48)"
  # …repeat for pguard-db-secrets (POSTGRES_PASSWORD, REPLICATION_PASSWORD, DATABASE_URL,
  #   DATABASE_READ_URL — the URLs embed the password, by design, mirroring compose),
  #   pguard-s3-secrets, pguard-otp-secrets, pguard-turn-secrets, pguard-grafana-secrets.
  ```

  Or use **sealed-secrets / external-secrets** so nothing sensitive lives in the repo. The
  `DATABASE_URL`/`DATABASE_READ_URL` values must stay consistent with `POSTGRES_PASSWORD`.

## Images / ghcr

The 14 custom images (`postgres-primary`, the 11 Rust services, `mediasoup`, `web-admin`) are
published to `ghcr.io/weiwutichai/pguard/<svc>` by `.github/workflows/deploy.yml`. They are
**private**, so pods need an imagePullSecret. Create one and attach it to the namespace's default
ServiceAccount (every pod inherits it — no per-manifest edits):

```bash
kubectl -n pguard create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io --docker-username=<gh-user> --docker-password=<gh-PAT-with-read:packages>
kubectl -n pguard patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}'
```

Pin a tag for rollbacks (from `overlays/staging`):
`kustomize edit set image ghcr.io/weiwutichai/pguard/api-gateway=ghcr.io/weiwutichai/pguard/api-gateway:<sha>` (repeat per image).

## Migrations

`migrate-job.yaml` runs a one-shot Job: `psql` connects DIRECTLY to the **primary**
(`postgres:5432`, bypassing pgbouncer — DDL belongs on the primary; the replica picks it up over
WAL) and applies every per-service migration in filename order, idempotently
(`public._k8s_migrations` ledger). Run it AFTER the DB is Ready, BEFORE/with the services.

The SQL is provided by a `pguard-migrations` ConfigMap created from the repo (one flat key per
file, `<svc>__<file>.sql`):

```bash
kubectl -n pguard create configmap pguard-migrations $(
  find contracts/db/migrations -mindepth 2 -name '*.sql' | sort | while read -r f; do
    printf -- '--from-file=%s=%s ' "$(echo "$f" | sed 's|contracts/db/migrations/||; s|/|__|')" "$f"
  done)
kubectl -n pguard apply -k infra/k8s/overlays/dev    # (re)creates the Job; it now finds the CM
# re-running the Job after a change: kubectl -n pguard delete job pguard-migrate && kubectl apply -k …
```

(For a real deploy you may prefer baking the SQL into a dedicated migration image instead of a
ConfigMap; the Job's runner script is image-agnostic.)

## Network-special — mediasoup & coturn (read before prod)

WebRTC needs the media/relay ports reachable by clients at their **real** host address, which k8s
ClusterIP/NodePort can't express for a wide contiguous UDP range. Both use **`hostNetwork: true`**
(binds the ports straight on the node, 1:1, exactly like the compose host publish). Consequences:

- **One pod per node** (two pods can't bind the same host range) → scale by adding nodes, **not
  replicas**; no HPA. Pin each with a `nodeSelector` to the node whose public IP you advertise.
- **`MEDIASOUP_ANNOUNCED_IP` / `TURN_EXTERNAL_IP` must equal that node's PUBLIC IP** (set per
  overlay — staging has `CHANGE_ME__node_public_ip` placeholders). A node behind CGNAT cannot
  relay; use a managed TURN (Twilio/Cloudflare) and point `TURN_URLS` at it.
- The **node firewall/security-group** must allow inbound ONLY: mediasoup `RTC_MIN..RTC_MAX/udp`
  (staging 42000–42199), coturn `3478/udp+tcp` + `50000–50100/udp`. The relay range is
  deliberately outside mediasoup's to avoid a collision. **DENY inbound mediasoup `3011/tcp`** (the
  SFU control plane) — under hostNetwork it would otherwise be node-reachable; it must stay
  in-cluster (calling → `http://mediasoup:3011`), unlike everything else which is internal by
  default. Compose kept 3011 on `expose` (internal); hostNetwork can't, so the firewall enforces it.
- hostNetwork pods are **outside NetworkPolicy scope** (intended — their ports are public).

## NetworkPolicy

`networkpolicy.yaml` is east-west defense-in-depth mirroring the compose posture (only the gateway
is reachable from outside; everything else is cluster-internal): **default-deny ingress** +
**allow same-namespace** (service↔service, DBs) + **allow ingress-nginx → gateway/web-admin only**.
Caveats: enforcement is **CNI-dependent** (kindnet ignores it); liveness/readiness probes come from
the kubelet — Calico/Cilium allow host→pod health checks by default, **verify on your CNI** or add a
host-range allow; the `ingress-nginx` namespaceSelector label may need adjusting to your install.

## Edge (Ingress) hardening — match the nginx.staging.conf controls

The Ingress reproduces the edge controls the proven nginx staging edge enforced; two depend on
**controller-level** config you must set (they can't live in the Ingress object alone):

- **X-Forwarded-For / client IP** — the gateway's per-IP rate limiter (OTP/auth brute-force,
  v1-audit risks #4/#5) trusts the left-most XFF hop. ingress-nginx's DEFAULT
  (`use-forwarded-headers: "false"`) overwrites XFF with the real peer — **keep it false**, exactly
  like nginx's `proxy_set_header X-Forwarded-For $remote_addr`. Only set it `"true"` if a trusted L7
  LB fronts the controller, and then ALSO pin `proxy-real-ip-cidr` to that LB — never open.
- **Edge rate limits** — coarse per-IP limits mirroring the nginx zones are set as first-class
  annotations: `/v1` + uploads 30 r/s, `/v1/auth` 5 r/s, `/v1/otp` 10 r/min. Defense-in-depth in
  front of the gateway's own Redis limiter.
- **Security headers** — the `pguard-web` Ingress carries the SPA's response headers (nosniff,
  X-Frame-Options, Referrer-Policy, Permissions-Policy, + HSTS) via a `configuration-snippet`
  (`more_set_headers`). This requires the controller flag **`allow-snippet-annotations: "true"`**
  (default false since ingress-nginx 1.9). If you keep snippets disabled, set the same headers via
  the controller's global **`add-headers` ConfigMap** or in the Next.js app's `headers()` — the
  manifest annotation is the documented default, those are the equivalents.
- **HTTPS redirect** — the staging overlay adds `force-ssl-redirect: "true"` to every Ingress.

## Verify

```bash
# Structural (no cluster needed) — both MUST exit 0 and validate clean:
kubectl kustomize infra/k8s/overlays/dev      | kubeconform -strict -summary -kubernetes-version 1.30.0
kubectl kustomize infra/k8s/overlays/staging  | kubeconform -strict -summary -kubernetes-version 1.30.0

# Runtime smoke on kind (stock images pull without auth; the 14 custom images need the
# ghcr imagePullSecret above, or build locally + `kind load docker-image pguard/<svc>:0.1.0`):
kind create cluster --name pguard-smoke
kubectl apply -k infra/k8s/overlays/dev
kubectl -n pguard rollout status statefulset/postgres-primary --timeout=180s
kubectl -n pguard rollout status statefulset/redis --timeout=120s
kubectl -n pguard rollout status statefulset/nats  --timeout=120s
# probe via port-forward / exec:
kubectl -n pguard port-forward svc/nats 8222:8222 & curl -s localhost:8222/healthz   # {"status":"ok"}
kubectl -n pguard exec sts/redis -- redis-cli ping                                   # PONG
kubectl -n pguard exec sts/postgres-primary -- pg_isready -U pguard -d pguard         # accepting connections
kind delete cluster --name pguard-smoke
```

> **Verification status (this PR):**
> - `kustomize build` — dev (73 resources) + staging (79) both exit 0 (71/77 ก่อน fold เพิ่ม auth/otp Ingress; นับใหม่หลัง fold).
> - `kubeconform -strict` — all valid for both overlays (0 errors, 0 skipped).
> - **kind** — on a real one-node `kind` cluster, applying the dev overlay's stock subset brought
>   **postgres-primary + redis + nats to Ready** with health probes responding (`pg_isready` →
>   *accepting connections*, `redis-cli ping` → *PONG*, nats `/healthz` → `{"status":"ok"}`), and the
>   **full dev overlay passed server-side validation** (รันก่อน fold ที่เพิ่ม 2 Ingress; post-fold ผ่าน kustomize+kubeconform) (`kubectl apply -k
>   overlays/dev --dry-run=server`) against the live API server. The 14 custom images
>   (identity, api-gateway, …) are private on ghcr, so on a real apply they ImagePullBackOff until
>   the imagePullSecret above is attached — proven via the stock subset + server dry-run per the
>   spec's documented fallback.

## Known limitations / TODO

- **Single-replica datastores** (postgres primary, nats, redis, minio, tempo, loki, grafana) — no
  HA yet; the read replica gives read scaling but failover is manual. HA (Patroni/operator,
  NATS cluster, Redis Sentinel) is a Round-2+ item.
- **prometheus scrape targets** were adapted from the compose file's `host.docker.internal:<port>`
  (dev-on-host) to in-cluster DNS — the single intentional config divergence (documented in
  `prometheus.yaml`).
- **cert-manager** not included — staging's Ingress references a `pguard-tls` Secret you create
  (or wire cert-manager + an Issuer). TODO.
- **CI deploy-to-k8s** job — out of scope (manual `kubectl apply -k` for now).
- Resource requests/limits are **conservative starting points** — tune from
  `../guard-dispatch/v2-audit/perf-baseline/results.md`.
- HPAs own the replica count of the services they target — don't also pin `replicas` there.

## compose → k8s env mapping (audit)

Every compose env var is preserved. Where it lives:

| compose source | k8s home |
|---|---|
| `x-rust-env`: `RUST_LOG`, `NATS_URL`, `REDIS_CACHE_URL`, `REDIS_PUBSUB_URL`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER_ARG` | ConfigMap `pguard-config` (envFrom on every service) |
| `x-rust-env`: `JWT_SECRET`, `EVENT_SIGNING_SECRET` + per-service `SERVICE_JWT_SECRET` | Secret `pguard-app-secrets` (envFrom on every service) |
| `x-db-env`: `POSTGRES_USER`, `POSTGRES_DB`, `DATABASE_MAX_CONNECTIONS`, `DATABASE_READ_MAX_CONNECTIONS` | ConfigMap `pguard-config` |
| `x-db-env`: `DATABASE_URL`, `DATABASE_READ_URL` (embed password), `POSTGRES_PASSWORD`, `REPLICATION_PASSWORD` | Secret `pguard-db-secrets` (envFrom on DB-backed services; discrete keys on the DB components) |
| `S3_ENDPOINT/BUCKET/REGION/PUBLIC_URL` (booking, chat) | ConfigMap `pguard-config` |
| `S3_ACCESS_KEY/S3_SECRET_KEY` = `MINIO_ROOT_USER/PASSWORD` | Secret `pguard-s3-secrets` |
| `INET_SMS_USERNAME/PASSWORD/SENDER` (otp) | Secret `pguard-otp-secrets`; `INET_SMS_URL` + OTP tunables inline on `otp` |
| `TURN_SECRET` (calling, coturn) | Secret `pguard-turn-secrets`; `STUN_URLS/TURN_URLS/TURN_CRED_TTL_SECS` inline on `calling`; coturn flags from env |
| `GRAFANA_ADMIN_PASSWORD` | Secret `pguard-grafana-secrets` |
| gateway `CORS_ALLOWED_ORIGINS`, `RATE_*`, `METRICS_ADDR`, `*_URL` upstream map | inline `env` on `api-gateway` (CORS patched per overlay) |
| `SMS_DISABLED` (otp), `FCM_DISABLED` (notification) | base = prod (SMS/push on); dev + staging overlays patch them off |
| `MEDIASOUP_ANNOUNCED_IP`, `RTC_MIN/MAX_PORT`; `TURN_EXTERNAL_IP`, `TURN_REALM`, `TURN_MIN/MAX_PORT` | inline `env` (announced/external IPs patched per overlay) |
| compose `ports:` (only api-gateway) | **Ingress** (gateway + web-admin); DBs/observability stay ClusterIP/headless (compose `expose`) |
| compose `healthcheck:` (`/healthz`, pg_isready, redis-cli, nats `/healthz`) | `readinessProbe`/`livenessProbe` per workload |
| compose `depends_on` | readiness probes + lazy DB pools (services recover once deps are Ready) |
| mediasoup/coturn host UDP publish | `hostNetwork: true` (see Network-special) |
