# pguard v2 — Observability (dashboards · alerts · SLOs)

Provisioned-as-code monitoring for the local **prod** stack (`docker-compose.prod.yml`): Prometheus
(metrics + alert rules), Grafana (datasources + dashboards), Tempo (traces), Loki (logs),
cross-linked for trace→logs→metrics correlation.

> Round 3-B added: a NATS/outbox-health dashboard, an edge/gateway dashboard, and **11 alert
> rules** whose thresholds are derived from the measured baseline + ceiling (not guessed). The
> numbers and their provenance are in [`tests/load/RESULTS.md`](../../tests/load/RESULTS.md) and
> [`v1-audit/perf-baseline/results.md`](../../v1-audit/perf-baseline/results.md).

## What's provisioned

| Kind | File | Notes |
|---|---|---|
| Datasources | `grafana/provisioning/datasources/datasources.yaml` | Prometheus (default) + Loki + Tempo, cross-linked |
| Dashboard | `grafana/provisioning/dashboards/pguard-overview.json` | per-service rate / p99 / 5xx / NATS lag |
| Dashboard | `…/pguard-nats-outbox.json` | consumer backlog, rejected events, liveness, outbox notes |
| Dashboard | `…/pguard-edge.json` | gateway status mix, **429 rate-limit hits**, p99, top routes |
| Scrape + rules ref | `prometheus.yml` | per-service `/metrics`; `rule_files: /etc/prometheus/rules/*.yml` |
| Alert rules | `prometheus/rules/pguard-alerts.yml` | 11 rules — latency / errors / 429 surge / NATS backlog / rejected events / liveness |

### Metrics actually exported (build against these, not wishes)

`http_requests_total{job,method,route,status}` · `http_request_duration_seconds_bucket{…,le}` ·
`nats_consumer_pending{durable}` · `nats_rejected_events_total{durable}` (+ `job` added at scrape;
lazily created on first rejection) · `up{job}` (Prometheus scrape liveness).

## SLOs (targets) + where the numbers come from

SLOs are **promises**; the alert thresholds sit at the **ceiling** so they catch real regression
without paging on normal load. Steady-state numbers are isolated single-endpoint p99; the
busy-hour numbers are the concurrent mixed-workload run (both in `RESULTS.md`).

| Endpoint class | Steady p99 (measured) | Busy-hour p99 (mixed) | SLO target | Alert (warn → crit) | Source |
|---|---|---|---|---|---|
| Auth (`identity` /auth/login) | ~134 ms | ~644 ms | p99 < 800 ms | **1 s → 2 s** (10m) | Argon2 CPU-bound; backend cliff ~30 login/s |
| General API (read/write) | < 30 ms | up to ~780 ms | p99 < 500 ms | **500 ms → 1.5 s** (10m) | discovery 30 ms iso / 782 ms mixed |
| 5xx error rate | 0 % | 0 % | < 1 % | **5 % → 20 %** (5m) | baseline 0 % on every path |
| Edge 429 (rate-limit) | ~0/s | ~0/s | n/a (by design) | **> 5/s** (10m) | per-IP limits: auth ~10/s, api ~50/s |
| NATS consumer backlog | 0 | — | ~0 | **> 50 → > 500** (5m) | chosen headroom (not a measured ceiling): baseline 0 + chaos shows transient spikes drain in seconds, so a 5m-sustained backlog = stuck. Tune to consumer throughput. |
| Rejected events | 0 | — | 0 | **> 0** (immediate) | fail-closed HMAC verify |
| Service liveness | up | — | up | **down 2m** | chaos case 4: clean 502, no cascade |

The general-API **warning at 500 ms is intentionally below the single-node busy-hour peak
(~780 ms)** — under a realistic concurrent mix one node is contention-bound, so the warning is the
**capacity signal to scale out** (see the HPA note below), while the 1.5 s critical flags genuine
degradation.

## Capacity → scaling (feeds the k8s HPA)

Measured ceilings (single laptop node, `RESULTS.md`):

- **identity is the tightest backend** — Argon2 verify is CPU-bound; throughput cliffs at
  **~30 login/s** (at 60/s offered, p99 blew to ~40 s and ~78 % errored). Scale identity on **CPU**,
  size replicas for peak login RPS, **min 2**.
- **discovery (booking-owned) ceilings ~100/s** (profile+rating service-JWT fan-out + replica reads);
  collapses by 300/s. Scale on CPU/RPS, **min 2**; the read replica already helps (C5.3 gate).
- **booking writes ~1000/s** and **GPS-WS ≥ 800 concurrent** with zero failures — ample headroom; not
  the constraint.
- The **edge per-IP rate limit binds first** for single-source traffic (auth ~10/s, api ~50/s) — by
  design (brute-force/abuse protection), not a capacity limit.

These map onto the HPA `averageUtilization` / `minReplicas` comments in the k8s manifests
("tune from perf baseline").

## Run it

```bash
# bring up the observability stack alongside the prod app stack
docker compose -f infra/docker/docker-compose.prod.yml up -d \
  otel-collector tempo loki prometheus grafana
# Grafana + Prometheus are cluster-internal (expose, not published). Tunnel to view:
ssh -L 9090:localhost:9090 -L 3000:localhost:3000 <host>   # or `docker compose port`
# verify the alert rules parse:
docker run --rm --entrypoint promtool \
  -v "$PWD/infra/observability/prometheus/rules:/rules:ro" \
  prom/prometheus:v2.55.1 check rules /rules/pguard-alerts.yml
```

Dashboards appear under the **pguard** folder; Prometheus → Status → Targets should show every
`job` `up`, and Status → Rules should list the 11 rules.

## Gaps (no metric today — documented, not invented)

- **Read-replica lag** — Postgres exports no Prometheus metric without `postgres_exporter` (not
  deployed). Replica lag is verified via SQL in the chaos suite; alerting on `pg_replication_lag`
  needs the exporter. **TODO:** add `postgres_exporter` sidecar + a `ReplicaLagHigh` rule.
- **pgbouncer pool saturation** — needs `pgbouncer_exporter` (not deployed). **TODO** likewise.
- **Active WS sessions** — neither the gateway WS proxy nor presence exports a live
  `ws_active_connections` gauge, so there is no edge-WS-sessions panel; the WS ceiling is
  characterised by `tests/load/ceiling-ws.js` instead. **TODO:** export the gauge.
- **Outbox depth** — no `outbox_pending` gauge is exported; drain is proven via SQL in chaos
  case 1. **TODO:** export it from the relay for a first-class panel/alert.

## Alertmanager routing (out of scope here — TODO)

These rules fire inside Prometheus but are **not yet routed** to Slack/email/PagerDuty — no
Alertmanager is wired. Sketch for the follow-up:

```yaml
# prometheus.yml (add):
alerting:
  alertmanagers:
    - static_configs: [{ targets: ["alertmanager:9093"] }]
# alertmanager.yml (new service):
route:
  receiver: pguard-oncall
  group_by: ['alertname', 'job']
  routes:
    - matchers: [severity="critical"]
      receiver: pguard-pager
receivers:
  - name: pguard-oncall
    slack_configs: [{ api_url: $SLACK_WEBHOOK, channel: '#pguard-alerts' }]
  - name: pguard-pager
    pagerduty_configs: [{ routing_key: $PD_KEY }]
```
