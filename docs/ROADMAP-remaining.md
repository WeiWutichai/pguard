# pguard v2 — Remaining Roadmap (~30% to production-ready)

> Snapshot: origin/main `14f687c`. Backend (12 services) + mobile (Flutter, full core) +
> web-admin foundation are merged, building green, and the prod stack builds/runs/replicates/serves.
> This roadmap covers what's left, batched into **rounds of 3 independent parallel tracks**
> (one per Claude Code terminal). Each track: own worktree off main, audited + merged before the
> next round. Ordering respects dependencies; within a round the three are independent.

---

## Round 0 — IN FLIGHT (current)
| Terminal | Track | Brings |
|---|---|---|
| A | **CI/CD pipeline** (#21) | auto build/test all stacks + image push → ghcr (replaces manual per-merge verify) |
| B | **v2 perf harness + replica init-fix** (#22) | stack boots fresh with no manual SQL · C5.3 perf numbers captured |
| C | **web-admin slice 2** (#23) | guards·customers·reviews·pricing·wallet·map real pages → admin ~80% |

**Exit:** core ≈ 88%. CI now guards every later round automatically.

---

## Round 1 — "testable & deployable end-to-end"
| Trk | Track | Why now | Notes |
|---|---|---|---|
| A | **e2e tests** — Playwright (web-admin) + Patrol (mobile) happy paths | web-admin + mobile are feature-complete enough to script flows | login→approve→book→track→chat; runs in CI |
| B | **k8s manifests** — `infra/k8s/` base + kustomize overlays (dev/staging) | compose proven; translate to k8s for real deploy | Deployments, Services, ConfigMaps/Secrets, HPA, gateway Ingress |
| C | **mediasoup media-plane** — full WebRTC wiring + calling e2e + RTC port config (the 41641/Tailscale conflict) | calling signaling done; media plane is the gap | configurable `RTC_MIN/MAX_PORT` + announced IP; prove a real audio/video call |

**Exit:** every flow has an e2e test · deployable to k8s · calling works end-to-end.

---

## Round 2 — "harden & complete"
| Trk | Track | Why now | Notes |
|---|---|---|---|
| A | **terraform IaC** — `infra/terraform/` | after k8s manifests exist | VPC/network, managed Postgres+replica, R2/S3, registry, secrets, the k8s cluster |
| B | **contract tests (Pact)** — `tests/contract/` | services + generated clients are stable | consumer (mobile/web) ↔ provider (each service) — catches contract drift CI-side |
| C | **web-admin polish** — dashboard (charts/metrics), activity log, settings, automation rules, recruitment/tasks | admin core pages done | Grafana-style overview, real metrics from services |

**Exit:** reproducible infra from code · contracts enforced · admin feature-complete.

---

## Round 3 — "production polish"
| Trk | Track | Why now | Notes |
|---|---|---|---|
| A | **real payment gateway** — replace simulated payments (Omise/2C2P/Stripe TH) | payment flow + refund ledger done; swap the gateway | webhooks, idempotency, reconciliation; keep the simulated path for dev |
| B | **load + chaos + dashboards** — k6 load beyond baseline, provisioned Grafana dashboards + alerts, failure injection | observability + perf baseline exist | find the real ceiling; SLO alerts |
| C | **security deepening** — NATS subject-ACL/account auth (beyond signed envelope), secret-rotation runbook, dependency/`cargo audit`, pen-test checklist | signed-envelope closed the forgery gap; go deeper | the bus-level authn the NATS slice flagged as follow-up |

**Exit:** production-ready ≈ 100% — real money path, known limits + alerting, bus-level auth.

---

## Dependency notes
- **CI/CD (R0-A) first** — once green, every later round's PR is auto-verified (less manual audit).
- **k8s (R1-B) before terraform (R2-A)** — terraform provisions the cluster the manifests target.
- **mediasoup (R1-C) before/with payment+load** — calling must work before load-testing it.
- e2e (R1-A) and contract (R2-B) both feed CI; e2e first (broader coverage), contract second (precision).

## Two ways to sequence (pick by goal)
- **Fastest to a polished demo:** R0 → R1-A(e2e) + R1-C(calling) + web-admin polish (pull R2-C up) → skip IaC/payment until later.
- **Fastest to real production:** R0 → R1 (all) → R2 (all) → R3 (all) — the order above.

## Not in scope / later
Real SMS send verification (INET prod), data-export UX polish, i18n audit, accessibility pass on web-admin, app-store packaging (iOS/Android signing), and any v1 data migration (N/A — v2 is greenfield).
