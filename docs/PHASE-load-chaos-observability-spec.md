# PHASE spec — Load + chaos + Grafana dashboards/alerts (หา ceiling จริง + SLO)

> **กลุ่ม B (Round 3-B):** ต่อยอด perf harness ที่มี baseline แล้ว → หาขีดจำกัดจริง
> + failure injection + dashboards/alerts แบบ provisioned
> **Worktree:** `feat/load-chaos-observability` off `main` (`da4e29a` ขึ้นไป)
> **เขตไฟล์:** `tests/load/` + `infra/observability/` + (`v1-audit/perf-baseline/`
> อ่าน/อ้างได้) + PROGRESS.md — ห้ามแตะ services/* apps/* (มี 2 slice ขนาน:
> security · codegen) · **ใช้ terminal เดียว**

---

## สถานะวันนี้ (จาก audit)

- Baseline จริงมีแล้ว (`v1-audit/perf-baseline/results.md`): auth p99 174ms ·
  discovery 25ms · writes <15ms · GPS WS 500 concurrent 0 fail · C5.3 gate PASS
  — k6 scripts 9 ตัวรันบน prod stack ผ่าน in-network
- Observability: Prometheus/Loki/Tempo/Grafana provisioned + datasources
  cross-linked แต่มี **dashboard เดียว 4 panels** · **ไม่มี alert rules เลย** ·
  metrics ที่มี: `http_requests_total`, `http_request_duration_seconds`,
  `nats_consumer_pending`, `nats_rejected_events_total`
- Chaos tooling: ไม่มี
- `tests/load/` = scaffold

## Scope of work

### A. Load — หา ceiling (ไม่ใช่แค่ re-run baseline)
1. ย้าย/ต่อยอด k6 เข้า `tests/load/` (reuse scripts + seed เดิม — อ้าง path
   เดิมได้ ไม่ copy ถ้า symlink/import ได้): **ramp จนพัง** ต่อ endpoint หลัก
   (login/discovery/booking-create/GPS-WS/chat) — บันทึก breaking point +
   bottleneck แรกที่ล้ม (DB pool? gateway? Argon2 CPU?)
2. Mixed-workload scenario (จำลองวันจริง: booking+GPS+chat พร้อมกัน สัดส่วน
   สมเหตุผล) — รันบน local prod stack; **อย่า load test ใส่ staging VPS โดย
   ไม่ระบุ** (ถ้าจะรันบน staging ให้เป็น opt-in script + เตือนใน README)
3. ผลลง `tests/load/RESULTS.md`: ceiling ต่อ scenario + bottleneck analysis +
   เทียบ baseline เดิม + คำแนะนำ scale (ผูกกับ HPA values ใน k8s ที่ comment
   ไว้ว่า "tune จาก perf baseline")

### B. Chaos — failure injection ขั้นต่ำที่พิสูจน์ resilience ที่ออกแบบไว้
เลือกเครื่องมือเบา (docker kill/pause/network delay ผ่าน script หรือ pumba —
justify) ทดสอบ + บันทึกพฤติกรรมจริง vs ที่ออกแบบ:
1. **NATS ตาย/กลับมา** — outbox ต้องค้างแล้ว drain ครบ (at-least-once พิสูจน์จริง)
2. **postgres-replica ตาย** — read routing fallback? (หรือ fail honest — บันทึก)
3. **redis ตาย** — rate limit / session degrade ยังไง gateway ยังรอดไหม
4. **service ตัวกลางตาย** (booking) — gateway 502 สวย ไม่ cascade
5. **WS proxy backend ตาย กลางคัน** — client ได้ Close + reconnect ได้
ผลลง `tests/load/CHAOS.md` + ถ้าเจอ bug จริง → จดเป็น finding (ห้ามแก้
service ใน slice นี้ — เปิด issue/PROGRESS item)

### C. Dashboards + alerts (provisioned เป็น code)
1. Dashboards เพิ่มใน `infra/observability/grafana/`: per-service overview
   (rate/p99/error ต่อ service จาก label เดิม) · NATS/outbox health
   (consumer_pending, rejected) · DB (pgbouncer/replica lag ถ้า metric มี —
   ถ้าไม่มี ระบุ gap อย่า invent) · edge (gateway rate-limit hits, WS sessions)
2. **Alert rules** (Prometheus rules file + provisioned): p99 > SLO ต่อ
   service · error rate >X% · `nats_consumer_pending` โต · replica lag ·
   container down — ค่า threshold อิงจาก baseline+ceiling ที่วัดได้จริงใน A
   (อย่าตั้งเลขลอยๆ — cite ที่มาใน comment)
3. SLO doc สั้นใน `infra/observability/README.md`: SLO ต่อ endpoint class +
   ที่มาของเลข

### Out of scope
แก้ bottleneck ที่เจอ (จดเป็น finding) · alertmanager → Slack/email wiring
(จด TODO + ตัวอย่าง config) · load test ใส่ k8s

## Definition of Done
1. Load suite รันได้ reproducible (README สั่งรันได้จริง) + RESULTS.md มี ceiling
   ตัวเลขจริงทุก scenario
2. Chaos ทั้ง 5 เคสรันจริง + CHAOS.md บันทึกผล (พฤติกรรมตรงดีไซน์ หรือ finding)
3. `docker compose config` ผ่าน (ถ้าแตะ provisioning mounts) · Grafana ขึ้น
   dashboards ใหม่จริงบน local stack (screenshot/บันทึกใน PR) · promtool check
   rules ผ่าน
4. `PROGRESS.md` tick + log row
5. own PR off main — ไม่ merge เอง

## Review gate
2 agents (code + architecture/SRE-มุมมอง) — จุดเพ่ง: ตัวเลข threshold มีที่มา ·
chaos ไม่แตะ service code · ไม่ load ใส่ staging โดย default
