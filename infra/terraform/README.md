<!-- pguard v2 — infra/terraform README (SCAFFOLD STUB) -->

# infra/terraform

Infrastructure-as-Code for pguard v2. **Scaffold placeholder — populated in
Phase 5 (Scale & harden).** Per `CLAUDE.md` → Service map (`infra/terraform/ IaC`).

## TODO (Phase 5)

- Provider + backend config (remote state).
- Managed Postgres (primary + read replica) — `CLAUDE.md` DB scaling decision.
- Object storage (Cloudflare R2 / S3) for docs + check-in photos.
- Managed Redis, NATS/JetStream cluster.
- Networking, DNS, TLS certs, secrets (no plaintext — pull from a secrets manager).
- Observability stack (Tempo / Loki / Prometheus / Grafana) targets.

Suggested module layout once started:

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
└── modules/
    ├── database/
    ├── object-store/
    └── observability/
```
