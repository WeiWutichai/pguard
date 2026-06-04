<!-- pguard v2 — infra/k8s README (SCAFFOLD STUB) -->

# infra/k8s

Kubernetes manifests for pguard v2. **Scaffold placeholder — populated in Phase 5
(Scale & harden).**

## Layout

```
k8s/
├── base/        # raw manifests shared by all envs (Deployment, Service, ...)
└── overlays/    # kustomize overlays per env (dev / staging / prod)
```

We use **kustomize** (base + overlays) rather than copy-pasted per-env YAML, per
`CLAUDE.md` → Service map (`infra/k8s/ base manifests + kustomize overlays`).

## TODO (Phase 5)

- `base/` — Deployment + Service + ConfigMap + HPA per Rust service, plus the
  StatefulSets for postgres / nats (JetStream) / redis and the observability
  stack.
- `base/kustomization.yaml` listing the resources.
- `overlays/{dev,staging,prod}/kustomization.yaml` with env patches
  (replicas, resource limits, image tags, secrets refs).
- pgbouncer + read-replica wiring (`CLAUDE.md` → DB scaling decision).
- ServiceMonitor / OTel collector DaemonSet for in-cluster observability.

Apply (once populated):

```bash
kubectl apply -k infra/k8s/overlays/dev
```
