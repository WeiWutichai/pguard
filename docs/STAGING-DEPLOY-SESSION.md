# Staging deploy — session handoff (VPS exec in progress)

> สำหรับเปิด chat ใหม่ต่อ. งานคือ deploy pguard v2 staging บน VPS ตาม `docs/STAGING-SETUP.md`.
> Cowork role: เขียน spec ให้ Claude Code, **audit ทุก deliverable ด้วย git จริง (ไม่เชื่อ report)**, merge เข้า main เอง, และตอนนี้ช่วย run/debug การ deploy บน VPS ทีละ step. ตอบไทย กระชับ.
> guard-dispatch = v1 reference อ่านอย่างเดียว ห้ามแก้ ห้าม copy code เข้า pguard.

---

## สถานะ repo (เสร็จแล้ว)
- `main = 46916ac` push ขึ้น origin แล้ว — v2 backend/infra ครบทุก slice + staging artifacts + orchestration specs/roadmap
- v2 = 14 custom images (api-gateway, identity, otp, profile, booking, payment, rating, calling, presence, chat, notification, mediasoup, web-admin, postgres-primary) + stock (nats:2-alpine, pgbouncer, coturn, redis, minio, postgres:17, observability)
- งาน slice ทั้งหมด task #1–#27 = completed

## VPS facts
- SSH: `ssh root@100.67.139.123` (Tailscale เท่านั้น, public 22 ปิด)
- public IPv4: **72.61.119.230** · domain `pguard.innoveraappcenter.com` (DNS ตรงแล้ว)
- ghcr owner `WeiWutichai` → path lowercase `weiwutichai/pguard` · packages private
- deploy dir VPS: `/root/pguard` (clone main 46916ac แล้ว) · v1 อยู่ `/root/guard-dispatch` (stop แล้ว เก็บไว้ reference)

## ทำไปแล้วบน VPS (STAGING-SETUP.md)
- [x] pre-flight: Docker 29.4 + Compose v2, disk 133G เหลือ
- [x] Step 1: `docker compose down` v1 — ปลดพอร์ต 80/443
- [x] Step 2: clone pguard → `/root/pguard` (HEAD 46916ac)
- [x] Step 3: DNS ตรง (dig = curl -s4 ifconfig.me = 72.61.119.230)
- [x] Step 4: `docker login ghcr.io -u WeiWutichai` → Login Succeeded (PAT read:packages)
- [x] Step 5: `cp .env.staging.example .env.staging` + เติม secrets ด้วย sed (hex ล้วน URL-safe):
      POSTGRES_PASSWORD/REPLICATION_PASSWORD/MINIO_ROOT_PASSWORD/GRAFANA_ADMIN_PASSWORD = `openssl rand -hex 24`;
      JWT_SECRET/SERVICE_JWT_SECRET/EVENT_SIGNING_SECRET/TURN_SECRET = `hex 48`;
      MINIO_ROOT_USER=pguard_minio; MEDIASOUP_ANNOUNCED_IP=TURN_EXTERNAL_IP=72.61.119.230 — `config -q` = OK
- [x] Step 6: cert มีอยู่แล้ว (v1 เดิม, Jun 8) `/etc/letsencrypt/live/pguard.innoveraappcenter.com/{fullchain,privkey}.pem` — ใช้ตัวเดิม ไม่ต้องออกใหม่
- [x] Step 7a: `pull` — ครบ 26 images
- [~] Step 7b: `up -d` — **กำลังแก้ปัญหา coturn port race (ดูด้านล่าง)**

## ปัญหาที่เจอ + แก้แล้ว: coturn UDP port race
- อาการ: `up -d` ล้ม `failed to bind host port 0.0.0.0:50042/udp: address already in use` (coturn relay 50000-50100 อยู่ใน Linux ephemeral pool 32768-60999 → kernel หยิบ 50042 ไป race ตอน docker-proxy bind)
- ลองย้าย TURN range → 30000-30049 แต่เจอ bug ที่ 2: compose `docker-compose.prod.yml:601` coturn ports = `"${TURN_MIN_PORT:-50000}-${TURN_MAX_PORT:-50100}:50000-50100/udp"` — ฝั่ง container **hardcode 50000-50100** (ไม่ symmetric เหมือน mediasoup บรรทัด 547) → `invalid ranges` เมื่อ host range ≠ 101 ports
- **วิธีแก้ที่ใช้:** คืน TURN เป็น default 50000-50100 (symmetric กับ container hardcode) + หด ephemeral range กัน kernel หยิบ ≥42000:
  ```
  sed -i -e 's|^TURN_MIN_PORT=.*|TURN_MIN_PORT=50000|' -e 's|^TURN_MAX_PORT=.*|TURN_MAX_PORT=50100|' infra/.env.staging
  sysctl -w net.ipv4.ip_local_port_range="32768 41999"
  echo 'net.ipv4.ip_local_port_range = 32768 41999' > /etc/sysctl.d/99-pguard-ports.conf
  ```
  ยืนยันแล้ว: `TURN range: 50000-50100 / ephemeral: 32768 41999` (กัน coturn 50000-50100 + mediasoup 42000-42199 จาก race)

## ขั้นต่อไป (ยังไม่ได้ทำ)
1. **re-run up -d** (ใน shell ที่ source .env.staging + export REGISTRY/IMAGE_PREFIX/IMAGE_TAG แล้ว):
   ```
   cd /root/pguard
   set -a; source infra/.env.staging; set +a
   export REGISTRY=ghcr.io IMAGE_PREFIX=weiwutichai/pguard IMAGE_TAG=latest
   docker compose -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.staging.yml up -d
   ```
   → ดูว่า coturn bind 50000-50100 ผ่าน + ทุก container Started. ถ้า mediasoup ยัง error → `up -d --scale mediasoup=0` (2-party call ใช้ coturn พอ)
2. **Step 7c migrate:**
   ```
   set -a; source infra/.env.staging; set +a
   tooling/scripts/migrate.sh
   ```
   (exec เข้า postgres ของ project `pguard-prod` — services ไม่ auto-migrate, replica รับ DDL ผ่าน WAL)
3. **ps + logs:** `... ps` ทุกตัว healthy · `... logs -f api-gateway nginx` ถ้าตัวไหน restart
   (replica base-backup ~1-2 นาที, start_period 120s — health: starting ช่วงแรกปกติ)
4. **Step 8 smoke test:**
   ```
   curl -fsS https://pguard.innoveraappcenter.com/v1/otp/challenge && echo
   curl -fsS https://pguard.innoveraappcenter.com/healthz && echo
   curl -fsSI https://pguard.innoveraappcenter.com/ | head -n1
   curl -sI http://pguard.innoveraappcenter.com/ | grep -i location
   docker compose -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.staging.yml exec postgres psql -U pguard -d pguard -c "SELECT client_addr,state,sync_state FROM pg_stat_replication;"
   ```
   ผ่าน = 8a JSON body + 8f มี row state=streaming

## TODO repo (แก้ทีหลังใน sandbox แล้ว push)
- **fix `infra/docker/docker-compose.prod.yml:601`** coturn ports ให้ symmetric เหมือน mediasoup:
  `"${TURN_MIN_PORT:-50000}-${TURN_MAX_PORT:-50100}:${TURN_MIN_PORT:-50000}-${TURN_MAX_PORT:-50100}/udp"`
  เพื่อให้ override TURN range ได้จริง (ตอนนี้ override ไม่ได้เพราะ container side hardcode)

## known limitations (จาก STAGING-SETUP.md)
- gateway ยังไม่ route chat/presence/calling/rating (+ WS /v1/ws/{chat,track,call}) → 404 ที่ edge จนกว่า gateway จะเพิ่ม route
- 1 MiB request-body cap ที่ /v1 (gateway buffer) · observability internal-only (เข้าผ่าน SSH tunnel)

## บทเรียน paste (สำคัญ)
- copy คำสั่งจาก Claude เอาเฉพาะบรรทัด command — อย่าลากคอมเมนต์ `# ...` ไทยมาด้วย (zsh/bash ตีความ glob เพี้ยน, รอบนี้เคยเผลอลบ .gitignore)
- multi-line ที่มี `\` ให้รวมเป็นบรรทัดเดียวเวลา paste (line continuation ขาดบ่อย)
- `source .env.staging` ผูกกับ shell session — เปิด tab/shell ใหม่ต้อง source + export ใหม่ก่อนรัน compose ทุกครั้ง
