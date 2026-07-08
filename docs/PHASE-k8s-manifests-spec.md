# PHASE spec — k8s manifests (Round 1-B: base + kustomize overlays)

> **Slice แรกของกลุ่ม B:** แปลง stack ที่พิสูจน์แล้วบน compose → Kubernetes
> (`infra/k8s/` ตอนนี้เป็น scaffold ว่าง) — เป็น dependency ของ terraform (Round 2)
> **Worktree:** `feat/k8s-manifests` off `main` (`6301f3b` ขึ้นไป)
> **แตะเฉพาะ `infra/k8s/` + docs + PROGRESS.md** — ห้ามแตะ services/* apps/*
> compose จริง (มี 2 slice ขนานอยู่) · **ใช้ terminal เดียว** · ห้ามแตะ `../guard-dispatch/`

---

## Source of truth

**`infra/docker/docker-compose.prod.yml` (+ staging overlay) คือสเปคที่พิสูจน์บน
VPS แล้ว** — แปลให้ตรง ไม่ invent: 14 custom images (ghcr) + stock
(postgres-primary/replica, pgbouncer, nats JetStream, redis, minio, coturn,
otel-collector, tempo, loki, prometheus, grafana) · env ทุกตัว (รวม `${VAR:?}`
fail-fast list) · healthchecks · depends_on ordering · port exceptions
(mediasoup UDP range, coturn) · `docs/STAGING-SETUP.md` มี gotchas ประกอบ

## Scope of work

### A. `base/` — แยกไฟล์ต่อ component ตาม convention
1. **Custom services (14):** Deployment + Service (ClusterIP) ต่อตัว — image
   `ghcr.io/.../pguard/<svc>` tag จาก kustomize · env จาก ConfigMap (non-secret)
   + Secret refs (ทุกตัวที่เป็น `${VAR:?}` ใน compose) · liveness/readiness จาก
   `/healthz` (พอร์ตตาม APP_PORT ใน compose) · resources requests/limits
   ตั้งค่าเริ่มแบบ conservative + comment ว่า tune จาก perf baseline
2. **Stateful (StatefulSet + PVC):** postgres-primary (custom image — มี
   replication init baked), postgres-replica, nats (JetStream file store),
   redis, minio · pgbouncer เป็น Deployment ปกติ (stateless)
3. **Network-special:**
   - mediasoup: UDP port range + announced IP → `hostNetwork` หรือ NodePort
     range — **เลือก+justify, document ข้อจำกัด** (นี่คือจุดที่ k8s ต่างจาก
     compose มากสุด อย่า silently เลือก)
   - coturn: เหมือนกัน (3478 + relay range) — แนะนำ host-level/NodePort +
     external-ip จาก env
4. **Ingress:** ทาง edge = แทน nginx.staging.conf — Ingress resource ส่ง
   `/v1/*` → api-gateway + `/` → web-admin + WS annotations
   (timeout/upgrade) + **per-path body-size annotation 12m สำหรับ 2 upload
   routes** (mirror nginx carve-out จาก PR #28; default 1m)
   อิง ingress-nginx annotations (ระบุ assumption ว่าใช้ ingress-nginx)
5. **Observability:** otel-collector/tempo/loki/prometheus/grafana — Deployment
   + ConfigMap จาก config files เดิมใน `infra/observability/`
6. **Migrations:** Job manifest รัน migrate (แพตเทิร์นจาก `migrate.sh` — psql
   ต่อ primary โดยตรง) — document ว่ารันยังไงต่อ rollout
7. **HPA:** ใส่เฉพาะ stateless ที่ scale ได้จริง (gateway, booking, identity, …)
   — target CPU เริ่มต้น + comment

### B. `overlays/` — kustomize
- `dev/` (replica 1, no HPA, secrets dummy ผ่าน secretGenerator example) ·
  `staging/` (image tags, host `pguard.innoveraappcenter.com`, TLS secret ref,
  replica จริง) — prod เว้นไว้เป็น TODO ชี้จาก README
- ห้าม commit secret จริง — `*.example` pattern เหมือน `.env.staging.example`

### C. Verify (DoD หลัก — ต้องรันได้จริง ไม่ใช่แค่เขียน YAML)
1. `kustomize build overlays/dev` + `overlays/staging` ผ่าน (exit 0)
2. **kubeconform** (หรือ kubeval) strict ผ่านทุก manifest
3. **kind cluster จริง**: `kind create cluster` → apply overlay dev (images
   stock pull ได้; custom 14 ตัวใช้ ghcr ถ้า pull ได้ หรือ document ว่า
   จุดไหนต้องการ imagePullSecret) → อย่างน้อย **postgres + redis + nats +
   identity + api-gateway ขึ้น Ready + `/healthz` ตอบ** ผ่าน port-forward —
   ถ้า image pull ติด auth ให้พิสูจน์ subset stock + document
4. README ใน `infra/k8s/` เขียนใหม่: prerequisites, สั่ง deploy, ลำดับ
   (secrets → db → migrate Job → services → ingress), known limitations
   (mediasoup/coturn networking)

### Out of scope
terraform (Round 2 — แต่เขียน base ให้ terraform ชี้ได้) · service mesh ·
cert-manager (จด TODO ใน README พอ) · CI deploy-to-k8s job

## Definition of Done
ข้อ C ทั้ง 4 + `PROGRESS.md` tick กลุ่ม B ข้อ k8s + log row + own PR off main
(ไม่ merge เอง)

## Review gate
2 agents (architecture + security) — จุดเพ่ง: secret ไม่หลุดเข้า repo · env ครบ
เทียบ compose ทุก service (diff เป็นตาราง) · ingress carve-out ตรง PR #28 ·
NetworkPolicy อย่างน้อยกั้น internal endpoints (หรือ document ว่า defer)
