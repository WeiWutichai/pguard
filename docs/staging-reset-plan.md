# แผนล้างข้อมูล Staging ให้เหลือเฉพาะ Admin — เอกสารเสนอเพื่อตัดสินใจ (ยังไม่ลงมือ)

> ขอบเขต: staging เท่านั้น (`pguard.innoveraappcenter.com`, compose project `pguard-prod`)
> เอกสารนี้เป็น **ข้อเสนอ** — ยังไม่มีการรันคำสั่งใด ๆ ต้องได้คำตอบใน §7 ก่อน

---

## สรุปสั้น (TL;DR)

- ฐานข้อมูลมี **10 schemas / 46 tables / 48 migration files**; FK มีแค่ **9 เส้น ทั้งหมดอยู่ใน schema เดียวกันและเป็น `ON DELETE CASCADE`** → **ลำดับการลบไม่ใช่ปัญหาจริง** ปัญหาจริงอยู่ที่อื่น
- **"Admin" = คอลัมน์เดียว: `identity.users.role = 'admin'`** ไม่มีตาราง admin, ไม่มี RBAC table, admin **ไม่มีแถวใน `profile.*` เลย**
- สิ่งที่ **ไม่ใช่ test data และไม่มีอะไรสร้างคืนให้อัตโนมัติ** มี 5 อย่าง: `booking.service_catalog`, `profile.org_settings`, `notification.automation_rules`, `notification.broadcasts`, `public._perf_migrations` — ถ้าลบไปแล้วต้องกรอกมือใหม่ทั้งหมด
- **การล้างแค่ Postgres ไม่พอ** ต้องล้าง **Redis (locks ผูกกับเบอร์โทร ไม่ใช่ user id)**, **MinIO (5 prefixes)**, **NATS JetStream (stream ไม่มีวันหมดอายุ)** และ **ล้าง app data บนเครื่องทดสอบ OPPO/Huawei** ในหน้าต่างเดียวกัน
- **แนะนำ Option B** (ล้างทุกตารางแบบระบุชื่อ + เก็บแถว admin + เก็บ config 5 อย่าง) — **ห้าม Option C (ลบ volume)** เพราะ **สร้าง admin ใหม่ไม่ได้ผ่านแอป** และมีกับดัก replica/bucket/migration ledger

---

## 1. ข้อมูลที่มีอยู่จริง — inventory ต่อ schema (46 tables)

สัญลักษณ์: 🗑️ = test data (ล้างได้) · 🔒 = config/admin-authored (**ห้ามล้าง**) · ⚙️ = machine state (ล้างได้แต่มีเงื่อนไข)

### `identity` (7 tables) — *ที่เดียวที่มีตัวตน admin*
| ตาราง | ประเภท | หมายเหตุ |
|---|---|---|
| `identity.users` | 🗑️/🔒 ผสม | **แถว `role='admin'` ต้องรอด** ที่เหลือลบได้ · แถวที่โดน PDPA soft-delete จะมี `phone` ขึ้นต้น `deleted:` — ยังนับเป็น test data |
| `identity.user_roles` | 🗑️ (FK CASCADE) | admin ปกติ **ไม่มีแถว** ก็ยังใช้งานได้ (`active_role_for` เชื่อ primary role เมื่อ set ว่าง) |
| `identity.refresh_tokens` | 🗑️ | ไม่มี FK — ต้องลบเอง |
| `identity.totp_recovery_codes` | 🗑️/🔒 | **ไม่มี FK** · ของ admin ที่เปิด 2FA = ทางหนีทางเดียว |
| `identity.api_tokens` | 🗑️/🔒 | **ไม่มี FK** · ของ admin = credential ของ CI/bot กู้คืนไม่ได้ (เก็บแค่ SHA-256) |
| `identity.credential_audit` | 🗑️ (FK CASCADE) | audit ต่อ user |
| `identity.processed_events` | ⚙️ | ledger กัน event ซ้ำ — ล้างพร้อม NATS เท่านั้น |

### `profile` (7 tables) — **ไม่มีแถว admin เลย** (write path บังคับ `require_role(GUARD/CUSTOMER)`)
`guard_profiles` 🗑️ (PII หนักสุด: เลขบัญชี/บัตร ปชช./DOB) · `customer_profiles` 🗑️ · `document_expiry` 🗑️ · `guard_assignments` 🗑️ (read-model จาก NATS) · `outbox` ⚙️ · `access_audit` 🔒? (PDPA §30 — ผูกกับ **admin id** ไม่ใช่ test user, ตัดสินใจแยก) · **`org_settings` 🔒 (แถวเดียว `id=TRUE`: ชื่อบริษัท/เลขภาษี บนใบเสร็จ + ในแอป)**

### `booking` (6 tables)
`bookings` 🗑️ · `progress_reports` 🗑️ (+รูปใน S3) · `guard_job_skips` 🗑️ · `outbox` ⚙️ · `processed_events` ⚙️ · **`service_catalog` 🔒 (แพ็กเกจ/ราคา — `create_booking` อ่าน `base_fee` จากตารางนี้จริง; ว่าง = แอปลูกค้าไม่มีแพ็กเกจให้เลือก และ booking ที่ส่ง `service_id` เก่าจะ 404)**

### `payment` (4 tables) — **ไม่มี config เลย ล้างได้ 100%**
`payments` 🗑️ · `payment_slips` 🗑️ (FK→payments CASCADE; +รูปสลิปใน S3; UNIQUE `trans_ref` = กันสลิปซ้ำ ล้างแล้วสลิปเดิมจ่ายได้อีก) · `outbox` ⚙️ · `processed_events` ⚙️

### `chat` (7 tables)
`conversations` 🗑️ (ไม่มีคอลัมน์ user เลย — filter ราย user เข้าไม่ถึง) · `participants`/`messages`/`read_receipts`/`attachments` 🗑️ (FK→conversations CASCADE) · `outbox` ⚙️ · `processed_events` ⚙️

### `rating` (2) `guard_reviews` 🗑️ · `outbox` ⚙️
### `calling` (2) `call_logs` 🗑️ · `outbox` ⚙️
### `presence` (3) `location_history` 🗑️ · `guard_locations` 🗑️ · `guard_assignments` 🗑️ (read-model)
### `otp` (1) `otp_codes` 🗑️ — **ผูกกับ phone ไม่ใช่ user_id**
### `notification` (7)
`fcm_tokens` 🗑️ (แอป re-register เองอัตโนมัติ) · `notification_logs` 🗑️ · `dispatch_recipients` 🗑️ · `outbox` ⚙️ · `processed_events` ⚙️ · **`broadcasts` 🔒 (`created_by` = admin; มี status `scheduled` ค้างอยู่ได้)** · **`automation_rules` 🔒 (`created_by` = admin)**

### นอก schema บริการ
**`public._perf_migrations` 🔒🔒🔒** — ledger ของ `tooling/scripts/migrate.sh` (48 แถว) **ห้ามแตะเด็ดขาด** (เหตุผลใน §3 Option C)

### ข้อเท็จจริงเชิงโครงสร้างที่ยืนยันแล้ว
- **FK ทั้งระบบมี 9 เส้น** ทุกเส้นอยู่ใน schema เดียวกันและเป็น `ON DELETE CASCADE`: `identity.user_roles`/`credential_audit`→`identity.users`; `chat.{participants,messages,read_receipts,attachments}`→`chat.conversations`; `booking.{progress_reports,guard_job_skips}`→`booking.bookings`; `payment.payment_slips`→`payment.payments` → **`DELETE` ไม่มีทางพัง FK ไม่ว่าเรียงยังไง** (แต่ `TRUNCATE` **ไม่** ตาม CASCADE ต้องใส่ทุกตารางในคำสั่งเดียว)
- **มี `INSERT INTO` ใน migration ทั้งต้นไม้แค่ 1 จุด**: `identity/0007_user_roles.sql:35-37` (backfill) และมันจะ **ไม่รันซ้ำ** เพราะ ledger
- Sequence มีแค่ 3 ตัว (BIGSERIAL: `identity.credential_audit`, `profile.access_audit`, `presence.location_history`) ไม่มีอะไรอ้างอิง → ไม่ต้อง reset

---

## 2. "Admin data" คืออะไรกันแน่ + อะไรอีกที่ต้องรอด

### 2.1 นิยาม admin (แม่นยำ)
```sql
-- นี่คือ "admin" ทั้งหมดที่มีในระบบ
SELECT id, phone, email, display_name, is_active, approval_status, deleted_at,
       totp_enabled, token_revocation_version
FROM identity.users WHERE role = 'admin';
```
แถวจะ **ล็อกอินได้จริง** ต่อเมื่อครบทั้ง 4: `role='admin'` **และ** `is_active=TRUE` **และ** `approval_status='approved'` **และ** `deleted_at IS NULL`

### 2.2 สิ่งที่ต้องเก็บของ admin
| ต้องเก็บ | จำเป็นไหม | สร้างใหม่ได้ไหม |
|---|---|---|
| `identity.users` (แถว admin, รวม `password_hash`) | **บังคับ** | ได้ แต่ต้องเขียน SQL + hash Argon2 เอง |
| `identity.users.totp_secret_enc` / `totp_enabled` / `totp_confirmed_at` | เฉพาะถ้าเปิด 2FA | **ไม่ได้** ต้อง enrol ใหม่ |
| `identity.totp_recovery_codes` (admin) | เฉพาะถ้าเปิด 2FA | **ไม่ได้** (SHA-256) |
| `identity.api_tokens` (admin, `revoked_at IS NULL`) | ถ้ามี CI/bot ใช้ | **ไม่ได้** (SHA-256 โชว์ครั้งเดียว) |
| `identity.user_roles` (admin) | ไม่จำเป็น | ได้ — และ **set ว่างปลอดภัยกว่า set ที่มี role อื่นแต่ไม่มี `admin`** (อันหลังจะโดน downgrade เงียบ ๆ แล้ว 403 ทั้งคอนโซล) |
| `identity.refresh_tokens` (admin) | ไม่จำเป็น | login ใหม่ได้ |
| `profile.*` | **ไม่มีอะไรเลย** | — |

### 2.3 ⚠️ ของที่ "ไม่ใช่ account แต่ก็ไม่ใช่ test data" — ต้องรอดด้วย
1. `booking.service_catalog` — ราคา/แพ็กเกจ (โค้ดมีแต่ soft-delete `is_active=false` ไม่เคย hard-delete)
2. `profile.org_settings` — ชื่อบริษัท/เลขภาษี (หายแล้ว fallback เป็น null เงียบ ๆ ไม่ error)
3. `notification.automation_rules`
4. `notification.broadcasts`
5. `public._perf_migrations`
6. (นโยบาย) `profile.access_audit` — PDPA §30 admin read trail

### 2.4 ⚠️ ข้อค้นพบที่ต้องตัดสินใจ: admin ที่มีอยู่อาจเป็น "test data" เอง
INSERT ของ admin ที่มีในรีโปมีที่เดียว: `v1-audit/perf-baseline/scripts/seed-v2.sql:37` →
`aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` / phone `0800000001` / `k6admin@t.local` / **hash ของ `Password123!` ที่ commit อยู่ในรีโปสาธารณะ**
ถ้า staging เคยถูก seed ด้วยไฟล์นี้ → "เก็บ admin ทุกแถว" = เก็บบัญชีที่ใครอ่านรีโปก็ล็อกอินได้ **ต้องตรวจก่อนและตัดสินใจรายแถว** (§7 Q1)

### 2.5 ⚠️ กับดักรหัสผ่าน web-admin (มีอยู่แล้ววันนี้ ไม่เกี่ยวกับการล้าง แต่กระทบ "สร้าง admin ใหม่")
- หน้า login ส่ง **รหัสดิบ** (`apps/web-admin/app/login/login-form.tsx`)
- หน้า Profile → เปลี่ยนรหัส ส่ง **SHA-256 hex** (`profile/page.tsx:162`) และ API บังคับ `validate_pin_hash` (64 hex)
→ **ไม่มี encoding เดียวที่ทำให้ทั้งสอง flow ทำงานพร้อมกัน** และ `POST /auth/reset-pin` จะย้ายบัญชีไปฝั่ง SHA-256 ถาวร
**ข้อสรุปเชิงปฏิบัติ: "เก็บแถว admin เดิมไว้" ปลอดภัยกว่า "ลบแล้วสร้างใหม่" อย่างมีนัยสำคัญ**

---

## 3. ทางเลือก 3 แบบ

### เตรียมการร่วม (ทำทุก Option — ห้ามข้าม)

```bash
# บน VPS, ที่ repo root
cd ~/pguard   # ปรับตามจริง
set -a; source infra/.env.staging; set +a
dc() { docker compose -f infra/docker/docker-compose.prod.yml -f infra/docker/docker-compose.staging.yml "$@"; }
PSQL=(docker exec -i pguard-prod-postgres psql -U pguard -d pguard -v ON_ERROR_STOP=1)

# P0 — สำรวจ admin ก่อนตัดสินใจอะไรทั้งสิ้น
"${PSQL[@]}" -c "SELECT id, phone, email, display_name, role, is_active, approval_status,
                        deleted_at, totp_enabled, token_revocation_version
                 FROM identity.users WHERE role='admin';"
"${PSQL[@]}" -c "SELECT id, user_id, name, prefix, last_used_at, revoked_at
                 FROM identity.api_tokens WHERE revoked_at IS NULL;"
"${PSQL[@]}" -c "SELECT count(*) FROM booking.service_catalog;"
"${PSQL[@]}" -c "SELECT * FROM profile.org_settings;"

# P1 — BACKUP (บังคับ). สอง layer: dump ทั้ง DB + dump เฉพาะของที่กู้ไม่ได้
docker exec pguard-prod-postgres pg_dump -U pguard -d pguard -Fc \
  > ~/pguard-staging-FULL-$(date +%Y%m%d-%H%M).dump
docker exec pguard-prod-postgres pg_dump -U pguard -d pguard \
  -t identity.users -t identity.user_roles -t identity.api_tokens \
  -t identity.totp_recovery_codes -t booking.service_catalog -t profile.org_settings \
  -t notification.automation_rules -t notification.broadcasts \
  > ~/pguard-keep-$(date +%Y%m%d-%H%M).sql
```

---

### Option A — **ลบแบบเลือกราย user** (ขยาย `staging-delete-guard.sh` ให้วนทุกเบอร์ที่ไม่ใช่ admin)

**ทำอะไร:** เก็บรายชื่อ user ที่ไม่ใช่ admin → ลบแถวที่ผูกกับ id/phone เหล่านั้นทีละ schema

**ขั้นตอน**
1. หยุด service ทั้งหมด (เหตุผลใน "ความเสี่ยง")
2. `CREATE TEMP TABLE wipe_users AS SELECT id, phone FROM identity.users WHERE role <> 'admin';` + เก็บ `booking_id` / `payment_id` / `conversation_id` ลง temp table **ก่อน** ลบ (เพราะ CASCADE จะกินคีย์ที่ต้องใช้ล้าง S3)
3. ล้าง S3 ตาม id ที่เก็บไว้ (5 prefixes)
4. รัน DELETE ตามแบบ `tooling/scripts/staging-delete-guard.sh` **แต่ต้องเติม 6 ตารางที่สคริปต์เดิมพลาด**: `booking.guard_job_skips`, `notification.dispatch_recipients`, `identity.api_tokens`, `identity.totp_recovery_codes`, `profile.access_audit`, `chat.conversations`
5. ล้าง Redis แบบเจาะจงต่อเบอร์ + `user_trv:{id}` ต่อ user
6. จัดการ outbox 7 ตัวแยกต่างหาก (filter ได้แค่ผ่าน JSONB path → seq scan)

**เวลา:** ~1–2 ชม. (ต้องเขียน+รีวิวสคริปต์ใหม่ ~60 บรรทัด)
**ทำลาย:** เฉพาะข้อมูลของ user ที่ไม่ใช่ admin
**เก็บ:** ทุกอย่างที่ไม่มีคอลัมน์ user — รวม config ทั้ง 5 และ **`processed_events` ทั้ง 5 ledger** (← ข้อดีสูงสุด: **ไม่มีความเสี่ยง JetStream replay เลย**)

**ความเสี่ยง**
- 17 ตารางไม่มีคอลัมน์ user → filter เข้าไม่ถึง (7 outbox + `chat.conversations` + 5 processed_events + …) → เหลือขยะ
- `chat.conversations` ไม่มีคอลัมน์ user เลย → ต้องลบด้วย `WHERE id NOT IN (SELECT conversation_id FROM chat.participants)` หลังลบ participants
- `otp.otp_codes` ผูก phone → ต้องใช้ list เบอร์ที่เก็บไว้
- ซับซ้อนที่สุด = โอกาสพลาดสูงสุด สำหรับเป้าหมายที่ผู้ใช้บอกว่า "ล้างใหม่หมด"

---

### Option B — **ล้างทุกตารางแบบระบุชื่อ + เก็บแถว admin + เก็บ config** ⭐ (แนะนำ)

**ทำอะไร:** `DELETE` แบบไม่มี WHERE ในทุกตารางที่เป็น test/machine data, ใช้ `WHERE ... NOT IN (admin ids)` เฉพาะ `identity.*`, และ **ไม่แตะ 5 ตาราง config + ledger**

**ขั้นตอน**

```bash
# B0 — ปิดผู้บริโภค/ผู้ผลิต event ทั้งหมด (กันเขียนซ้อนระหว่างล้าง และกันโทเคนที่ยังไม่หมดอายุเขียนข้อมูลกลับ)
dc stop api-gateway identity profile otp notification booking payment rating calling presence chat mediasoup web-admin

# B1 — ตรวจ outbox ต้องระบายหมดก่อน (ทั้ง 7 ตัว ต้องได้ 0 ทุกบรรทัด)
"${PSQL[@]}" -c "
SELECT 'booking' s, count(*) FROM booking.outbox      WHERE published_at IS NULL
UNION ALL SELECT 'payment', count(*) FROM payment.outbox      WHERE published_at IS NULL
UNION ALL SELECT 'chat',    count(*) FROM chat.outbox         WHERE published_at IS NULL
UNION ALL SELECT 'rating',  count(*) FROM rating.outbox       WHERE published_at IS NULL
UNION ALL SELECT 'calling', count(*) FROM calling.outbox      WHERE published_at IS NULL
UNION ALL SELECT 'profile', count(*) FROM profile.outbox      WHERE published_at IS NULL
UNION ALL SELECT 'notif',   count(*) FROM notification.outbox WHERE published_at IS NULL;"
```

> ถ้าไม่เป็น 0: ให้ start service นั้นสัก 30 วิ ให้ relay ระบาย แล้ว stop ใหม่ — **อย่าลบ `profile.outbox` ที่ยัง `published_at IS NULL` ทิ้งโดยที่ user นั้นจะรอด** เพราะแถวนั้นคือ "การอนุมัติที่ identity ยังไม่เห็น" ลบแล้ว user ค้าง login-blocked ถาวรไม่มีทาง retry (กรณีนี้เราลบ user นั้นอยู่แล้ว จึงไม่เป็นปัญหา)

```sql
-- B2 — Postgres wipe (transaction เดียว, ระบุชื่อทุกตาราง, ไม่มี TRUNCATE, ไม่แตะ public.*)
BEGIN;

CREATE TEMP TABLE keep_users AS
  SELECT id FROM identity.users WHERE role = 'admin';
-- ถ้าต้องการเก็บเฉพาะบาง admin ให้แก้เป็น: WHERE id IN ('<uuid1>','<uuid2>')

-- chat (ลูกก่อน แม้จะ CASCADE อยู่แล้ว)
DELETE FROM chat.attachments;
DELETE FROM chat.read_receipts;
DELETE FROM chat.messages;
DELETE FROM chat.participants;
DELETE FROM chat.conversations;
DELETE FROM chat.outbox;
DELETE FROM chat.processed_events;

-- booking  (KEEP: booking.service_catalog)
DELETE FROM booking.progress_reports;
DELETE FROM booking.guard_job_skips;
DELETE FROM booking.bookings;
DELETE FROM booking.outbox;
DELETE FROM booking.processed_events;

-- payment
DELETE FROM payment.payment_slips;
DELETE FROM payment.payments;
DELETE FROM payment.outbox;
DELETE FROM payment.processed_events;

-- rating / calling / presence
DELETE FROM rating.outbox;
DELETE FROM rating.guard_reviews;
DELETE FROM calling.outbox;
DELETE FROM calling.call_logs;
DELETE FROM presence.location_history;
DELETE FROM presence.guard_locations;
DELETE FROM presence.guard_assignments;

-- notification  (KEEP: automation_rules, broadcasts)
DELETE FROM notification.dispatch_recipients;
DELETE FROM notification.notification_logs;
DELETE FROM notification.fcm_tokens;
DELETE FROM notification.outbox;
DELETE FROM notification.processed_events;

-- profile  (KEEP: org_settings ; access_audit = ตัดสินใจใน §7 Q4)
DELETE FROM profile.guard_assignments;
DELETE FROM profile.document_expiry;
DELETE FROM profile.guard_profiles;
DELETE FROM profile.customer_profiles;
DELETE FROM profile.outbox;
-- DELETE FROM profile.access_audit;            -- เปิดใช้ก็ต่อเมื่อตอบ Q4 ว่า "ล้าง"

-- otp (phone-keyed)
DELETE FROM otp.otp_codes;

-- identity — ลูกก่อน พ่อทีหลัง, เก็บเฉพาะ admin
DELETE FROM identity.credential_audit    WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.user_roles          WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.refresh_tokens      WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.totp_recovery_codes WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.api_tokens          WHERE user_id NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.users               WHERE id      NOT IN (SELECT id FROM keep_users);
DELETE FROM identity.processed_events;   -- ต้องทำคู่กับการ reset NATS ใน B3 เท่านั้น

COMMIT;
```

3. **B3 = NATS**, **B4 = Redis**, **B5 = MinIO** → ดู §5 (บังคับ ทำในหน้าต่างเดียวกัน)
4. `dc up -d` แล้วรัน §6 verification
5. ล้าง app data บนเครื่องทดสอบ

**เวลา:** ~15–25 นาที (downtime จริง ~10–15 นาที)
**ทำลาย:** ข้อมูลทดสอบทุกอย่าง (users/bookings/payments/chat/ratings/presence/notifications) + machine state + ไฟล์ใน S3 ทั้งหมด
**เก็บ:** แถว admin (+2FA/api_tokens ของ admin), `booking.service_catalog`, `profile.org_settings`, `notification.automation_rules`, `notification.broadcasts`, `public._perf_migrations`, schema/enum/index ทั้งหมด

**ความเสี่ยง & มาตรการ**
| ความเสี่ยง | มาตรการ |
|---|---|
| ล้าง `processed_events` ทั้ง 5 แต่ JetStream ยังเก็บ event เดิม (stream ไม่มี `max_age`) → replay ได้ | **B3 บังคับ**: recreate container `nats` ในหน้าต่างเดียวกัน (ล้างทั้งสองฝั่งพร้อมกัน) |
| `presence-booking-links` / `profile-booking-links` **ไม่มี ledger เลย** เป็น `INSERT … ON CONFLICT DO UPDATE` → replay จะ **สร้างแถว `guard_assignments` ของ booking ที่ลบไปแล้วคืนมา** | ข้อเดียวกัน — reset NATS |
| DELETE ขณะ service ยังรัน → lock ค้าง + replica read เพี้ยน | B0 stop ก่อน |
| Access token อายุ 15 นาทีของ user ที่ถูกลบยังเขียนข้อมูลกลับได้ (auth ไม่แตะ DB) | B0 stop + FLUSHALL |
| `identity.user_roles` ของ admin หายแล้ว backfill ไม่รันซ้ำ | ไม่เป็นปัญหา — set ว่าง = เชื่อ primary role (มี unit test ยืนยัน) แต่ **ห้ามใส่แถว role อื่นให้ admin เดี่ยว ๆ** |
| ลบ `payment.payment_slips` = ปลด UNIQUE `trans_ref` → สลิปเดิมจ่ายซ้ำได้ | ถูกต้องสำหรับ test data; ถ้า staging เคยรับสลิปจริงต้องบันทึกไว้ (§7 Q5) |

---

### Option C — **ลบ volume + re-migrate + สร้าง admin ใหม่** ❌ (ไม่แนะนำอย่างยิ่ง)

**ทำอะไร:** `dc down -v` → `up -d` → `migrate.sh` → เขียน SQL สร้าง admin ใหม่
**เวลา:** ~30–60 นาที ถ้าไม่ติดกับดัก / **หลายชั่วโมงถ้าติด**
**เก็บ:** ไม่มีอะไรเลย

**เหตุผลที่ปฏิเสธ — 6 กับดัก ทุกข้อยืนยันจากไฟล์จริง**
1. **สร้าง admin ผ่านแอปไม่ได้** — ไม่มี bootstrap script / env `ADMIN_PHONE` / seed migration; `domain/registration.rs:14` ปฏิเสธ `admin` ทุกเส้นทาง → ต้องเขียน Argon2 hash + raw INSERT เอง และไปเจอกับดักรหัสผ่านใน §2.5
2. **`DROP SCHEMA … CASCADE` + `migrate.sh` = ไม่สร้างอะไรเลย** — ledger อยู่ที่ `public._perf_migrations` (นอก schema) → รายงาน "48 already-applied" แต่ไม่มีตารางเลย และ **healthz ยังเขียว** (healthz เป็น JSON literal; readyz probe แค่ Redis) → API 500 ทุกเส้น
3. **ลบ `pg-data` แต่ไม่ลบ `pg-replica-data`** → replica ไม่ re-basebackup (เช็ค `PG_VERSION`), เปิด read-only ได้ (health ผ่าน, service boot ได้) แต่ walreceiver ตายถาวร → `DATABASE_READ_URL` เสิร์ฟ **ข้อมูลเก่าก่อนล้าง** ให้ทุกหน้า list/report
4. **`down -v` ลบ MinIO bucket** — bucket `pguard` ถูกสร้างด้วยมือครั้งเดียว (`docs/STAGING-SETUP.md:129`) ไม่มีโค้ดสร้างให้ → อัปโหลดทุกอย่าง 500 จนกว่าจะ `mc mb` + `mc anonymous set none` ใหม่ (ลืมข้อหลัง = เปิดบัตร ปชช. รปภ. ให้คนทั่วไป)
5. **migration ไฟล์ไม่ idempotent** — `CREATE TABLE` 41 จุดไม่มี `IF NOT EXISTS`, `profile/0009` มี `CREATE INDEX CONCURRENTLY` ที่ไม่มี guard และ ledger เขียน**หลัง**ไฟล์จบ → ล้มกลางไฟล์ = ค้างถาวร
6. **`deploy-staging.sh` step 5/7 รัน `migrate.sh` ทุกครั้ง** ภายใต้ `set -euo pipefail` → ถ้า ledger เพี้ยน **deploy ครั้งถัดไปตายก่อนถึง step 6 (force-recreate nginx) → edge 502**

**ควรใช้เมื่อไร:** เฉพาะกรณีต้องการเปลี่ยน schema แบบ destructive หรือ DB เสียหายจนกู้ไม่ได้ และยอมรับว่าต้องสร้าง admin ใหม่ด้วยมือ

---

## 4. คำแนะนำ

### ✅ เลือก **Option B**

เหตุผล:
1. **ตรงเป้าหมายที่ผู้ใช้บอกจริง ๆ** — "ล้างใหม่หมด เหลือแค่ admin" คือ full wipe ไม่ใช่ selective delete
2. **ไม่แตะ DDL / ledger เลย** → ไม่มีกับดัก migration, ไม่มีกับดัก replica, ไม่มีกับดัก bucket, pgbouncer ไม่เจอ `cached plan must not change result type` (relfilenode เปลี่ยน แต่ OID ไม่เปลี่ยน)
3. **เก็บแถว admin เดิมไว้ ไม่ต้องสร้างใหม่** → หลบกับดักรหัสผ่าน raw-vs-SHA256 และหลบการสูญเสีย 2FA/api_tokens ทั้งหมด
4. **ระบุชื่อทุกตาราง** → ไม่มีทางเผลอกิน `public._perf_migrations` หรือ config
5. เร็วกว่า A มาก และปลอดภัยกว่าเพราะ **ไม่ต้องเขียนสคริปต์ใหม่ที่ต้องรีวิว** — เป็น SQL ตายตัวที่อ่านทวนได้ทั้งก้อน

**ข้อแลกเปลี่ยนที่ยอมรับ:** B ต้อง reset NATS ด้วย (A ไม่ต้อง) — แต่ NATS store บน staging เป็น ephemeral อยู่แล้ว (ไม่มี volume) การ recreate container จึงถูกและปลอดภัย ตราบใดที่ทำ**พร้อมกัน**กับการล้าง `processed_events`

**ถ้าจะเลือก A แทน** — เหมาะกรณีเดียว: ต้องการเก็บ booking/rating ในอดีตไว้ดูสถิติ ซึ่งขัดกับคำขอ

---

## 5. การล้างนอก Postgres (บังคับทุก Option)

> **ข้อนี้สำคัญที่สุดในเอกสาร** — ที่ผ่านมาอาการ "ลบ account แล้วแต่ยังขึ้น ขอ OTP เกินจำนวนที่กำหนด" เกิดจากตรงนี้ล้วน ๆ

### 5.1 NATS JetStream — **ทำก่อน Redis/S3**
stream `PGUARD_EVENTS` subject `pguard.events.>` สร้างด้วย `..Default::default()` = **file storage, `max_age=0` (ไม่หมดอายุ), `max_msgs=-1`** มี durable consumer **11 ตัว** และ 2 ตัวในนั้น (`presence-booking-links`, `profile-booking-links`) **ไม่มี idempotency ledger เลย**

```bash
# NATS ไม่มี volume (compose mount แค่ nats.conf) และ jetstream ใช้ store แบบ ephemeral
# → recreate container = ล้าง stream + ack floor ของทั้ง 11 durable พร้อมกัน
dc rm -sfv nats
dc up -d nats
```
⚠️ `docker restart nats` **ไม่ล้าง** — ต้อง `rm -sfv` เท่านั้น
⚠️ ห้ามล้าง `processed_events` โดยไม่ทำข้อนี้ และห้ามทำข้อนี้โดยไม่ล้าง `processed_events` — **ต้องคู่กันเสมอ**

### 5.2 Redis — key ผูกกับ **เบอร์โทร** ไม่ใช่ user id
| key | TTL | ผลถ้าไม่ล้าง |
|---|---|---|
| `otp_lock:{phone}` | สูงสุด **86400s (24 ชม.)** | เบอร์ทดสอบเดิมสมัครใหม่แล้วขึ้น "กรุณาติดต่อเจ้าหน้าที่" นาน 24 ชม. บน DB ที่ว่างเปล่า — และ **ปลดล็อกเองไม่ได้** เพราะ counter เคลียร์เมื่อ verify สำเร็จเท่านั้น แต่ lock เช็คก่อนขอ OTP |
| `otp_daily:` / `otp_burst:` / `otp_rate:{phone}` | 86400 / 600 / n | โควตาถูกเผาไปแล้ว |
| `login_fail:` / `login_lock:{identifier}` | 900s / 60→1800s | 401 ไม่มีคำอธิบาย |
| **`user_trv:{user_id}`** | **ไม่มี TTL โดยเจตนา** | ถ้าสร้าง user ใหม่ด้วย **UUID เดิม** (เช่น `aaaaaaaa-…` จาก seed) → token ใหม่ทุกใบ 401 ถาวร โดยไม่มีร่องรอยใน DB |

```bash
docker exec pguard-prod-redis redis-cli FLUSHALL
```
**ปลอดภัยกับ admin ที่เก็บไว้:** ลบ `user_trv:{admin_id}` = marker หายไป → ถือเป็น 0 → token ใหม่ที่ trv=N ผ่านปกติ
⚠️ redis ไม่มี **named** volume แต่ image `redis:7` ประกาศ `VOLUME /data` → มี anonymous volume เก็บ `dump.rdb` ข้ามการ recreate → **ต้องใช้ `FLUSHALL` อย่าหวังพึ่งการ restart container**

### 5.3 MinIO — bucket เดียว `pguard`, **5 prefixes**, ไม่มีโค้ดไหนลบให้เลย
| prefix | เจ้าของ | เนื้อหา |
|---|---|---|
| `profile/{user_id}/documents/` | profile | **บัตร ปชช. / ใบอนุญาต — PDPA หนักสุด** |
| `profile/{user_id}/avatar/` | profile | รูปโปรไฟล์ |
| `booking/{booking_id}/checkins/` | booking | รูปเช็กอินรายชั่วโมง |
| `payment/{payment_id}/slips/` | payment | **สลิปโอนเงิน — PII ธนาคาร** |
| `chat/{conversation_id}/` | chat | ไฟล์แนบ |

```bash
docker exec pguard-prod-minio sh -c \
 'mc alias set local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1;
  mc rm --recursive --force local/pguard/profile/ ;
  mc rm --recursive --force local/pguard/booking/ ;
  mc rm --recursive --force local/pguard/payment/ ;
  mc rm --recursive --force local/pguard/chat/'
```
⚠️ **ห้าม `mc rb`** (ลบ bucket) — สร้างใหม่ต้อง `mc anonymous set none` ด้วย ลืม = เปิดสาธารณะ
⚠️ Option B ลบข้อมูลทั้งหมดอยู่แล้ว → ล้างทั้ง prefix ได้เลย (admin ไม่มีไฟล์ใน S3 เพราะไม่มีแถวใน `profile.*`)
⚠️ ถ้าลบ DB ก่อนล้าง S3 จะ**หา id ไม่เจออีกเลย** ไฟล์ยังอ่านได้จาก MinIO console แต่แอปเข้าไม่ถึง → ต้องล้าง S3 **ก่อนหรือทันทีหลัง** commit

### 5.4 เครื่องทดสอบ (OPPO + Huawei) — **สถานะฝั่ง client ไม่หายไปกับการล้าง server**
`FlutterSecureStorage` เก็บ `pg_access_token`, `pg_refresh_token`, `pg_phone`, `pg_pin_hash`, `pg_pin_salt`, `pg_pin_attempts`, `pg_pin_lock_until_ms`, `pg_biometric_enabled`, `pg_installed_v1`, `pg_reg_*`
→ แอปจะยัง "ดูเหมือนล็อกอินอยู่", เด้งเข้าหน้า PIN ของเบอร์ที่ไม่มีแล้ว, และ `pg_pin_attempts` จะไต่ไปหา 10 ครั้งจนแอป `deleteAll()` เอง

```
Android: Settings → Apps → pguard → Storage → Clear data   (ทั้งสองเครื่อง)
หรือ:    adb uninstall <package> แล้วติดตั้ง APK ใหม่
```

### 5.5 ที่ **ห้ามแตะ**
`${OSRM_DATA_DIR}` (แผนที่ไทย สร้างใหม่แพงมาก) · `/etc/letsencrypt` + `/var/www/certbot` · `infra/docker/secrets/fcm-service-account.json` · `infra/.env.staging` · `grafana-data`/`tempo-data`/`loki-data` (จะล้างก็ได้ ไม่บังคับ)

---

## 6. การตรวจสอบหลังล้าง

```bash
dc up -d
sleep 30
```

**6.1 บริการขึ้นครบ + edge ตอบ**
```bash
dc ps
curl -fsS -o /dev/null -w "edge healthz -> %{http_code}\n" https://pguard.innoveraappcenter.com/healthz
```

**6.2 Migration ledger สมบูรณ์ (ต้องได้ 48 และ schema ครบ 10)**
```sql
SELECT count(*) AS ledger_rows FROM public._perf_migrations;            -- ต้อง = 48
SELECT count(*) AS tables FROM information_schema.tables
 WHERE table_schema IN ('identity','profile','otp','booking','payment',
                        'rating','calling','presence','chat','notification');  -- ต้อง = 46
```

**6.3 Admin รอด + ไม่มี user อื่นเหลือ**
```sql
SELECT id, phone, email, role, is_active, approval_status, deleted_at, totp_enabled
  FROM identity.users;                          -- ต้องเหลือเฉพาะ admin ที่ตั้งใจเก็บ
SELECT count(*) FROM identity.users WHERE role <> 'admin';   -- ต้อง = 0
```

**6.4 Config รอดครบ**
```sql
SELECT count(*) AS services      FROM booking.service_catalog;        -- ต้อง > 0
SELECT count(*) AS active_svc    FROM booking.service_catalog WHERE is_active;  -- ต้อง > 0
SELECT * FROM profile.org_settings;                                   -- ต้องมี 1 แถว
SELECT count(*) FROM notification.automation_rules;
SELECT count(*) FROM notification.broadcasts;
```

**6.5 Test data ว่างจริง**
```sql
SELECT 'bookings' t, count(*) FROM booking.bookings
UNION ALL SELECT 'payments',      count(*) FROM payment.payments
UNION ALL SELECT 'guard_profiles',count(*) FROM profile.guard_profiles
UNION ALL SELECT 'cust_profiles', count(*) FROM profile.customer_profiles
UNION ALL SELECT 'reviews',       count(*) FROM rating.guard_reviews
UNION ALL SELECT 'chats',         count(*) FROM chat.conversations
UNION ALL SELECT 'presence_loc',  count(*) FROM presence.guard_locations
UNION ALL SELECT 'otp_codes',     count(*) FROM otp.otp_codes;        -- ทุกบรรทัดต้อง 0
```

**6.6 Admin ล็อกอินได้จริง (ทดสอบจริง ไม่ใช่แค่ query)**
```bash
curl -i -X POST https://pguard.innoveraappcenter.com/v1/auth/login \
  -H 'content-type: application/json' \
  -d '{"identifier":"<admin_phone>","password":"<รหัสดิบ>"}'
# คาดหวัง 200 + Set-Cookie: access_token, refresh_token (httpOnly)
# ถ้าได้ {"two_factor_required":true,...} = admin เปิด 2FA อยู่ → หน้า login ของ web-admin
#   ยังไม่รองรับ branch นี้ (จะเด้งกลับ /login วนลูป) ดู §7 Q3
```
แล้วเปิดเบราว์เซอร์ (**hard refresh**) → `https://pguard.innoveraappcenter.com/` → ต้องเข้า `/dashboard` ได้ และหน้า Guards/Customers/Bookings ต้องว่างเปล่า (ไม่ใช่ error)

**6.7 Replica ไม่ค้าง (ถ้าเลือก Option B ไม่ควรมีปัญหา แต่ควรตรวจ)**
```bash
docker exec pguard-prod-postgres psql -U pguard -d pguard -c \
  "SELECT client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication;"
# ต้องมี 1 แถว state='streaming'
docker exec pguard-prod-postgres-replica psql -U pguard -d pguard -tAc \
  "SELECT count(*) FROM identity.users;"   # ต้องได้ตัวเลขเดียวกับ primary
```

**6.8 NATS ตั้งต้นใหม่**
```bash
dc logs --tail 50 nats | grep -i jetstream
dc logs --tail 100 booking | grep -iE 'stream|consumer'   # ต้องเห็นการ create ใหม่ ไม่มี error
```

**6.9 End-to-end บนมือถือ (การพิสูจน์ที่แท้จริง)**
สมัคร guard ใหม่ 1 คน + customer ใหม่ 1 คน ด้วยเบอร์ทดสอบเดิม → ต้อง **ขอ OTP ได้ทันที** (ถ้าขึ้น "ขอ OTP เกินจำนวนที่กำหนด" = Redis ยังไม่ถูกล้าง กลับไปทำ §5.2) → admin approve → จอง → จ่าย → เช็กอิน → จบงาน → rate

---

## 7. คำถามที่ต้องตอบก่อนลงมือ

| # | คำถาม | ทำไมสำคัญ |
|---|---|---|
| **Q1** | รัน query ใน "เตรียมการร่วม P0" แล้วบอกว่า **มี admin กี่แถว, UUID/เบอร์อะไรบ้าง** และ **แถวไหนต้องเก็บ** | ถ้ามีแถว `aaaaaaaa-aaaa-…` / เบอร์ `0800000001` / `k6admin@t.local` = admin จาก seed ที่ **รหัส `Password123!` อยู่ในรีโปสาธารณะ** → ควรลบทิ้งหรือเปลี่ยนรหัส ไม่ใช่เก็บไว้ |
| **Q2** | admin ที่จะเก็บ **จำรหัสผ่านได้ไหม** และเคยกด "เปลี่ยนรหัสผ่าน" ในหน้า Profile ของ web-admin ไหม | ถ้าเคยกดสำเร็จ บัญชีจะย้ายไป encoding SHA-256 → ต้องพิมพ์ digest 64 hex เป็นรหัสผ่านถึงจะเข้าได้ ต้องรู้ก่อนเพราะเราจะ **ไม่** สร้างใหม่ |
| **Q3** | admin **เปิด 2FA (TOTP) อยู่หรือไม่** (`totp_enabled` จาก Q1) | ถ้าเปิด: หน้า login ของ web-admin ยังไม่มี branch `two_factor_required` → เด้งวนลูป ต้องปิดด้วย SQL ก่อน (`UPDATE identity.users SET totp_enabled=FALSE, totp_secret_enc=NULL WHERE id=…`) — เป็นบั๊กที่มีอยู่แล้ว ไม่เกี่ยวกับการล้าง |
| **Q4** | `profile.access_audit` (PDPA §30 admin read trail) — **ล้าง / เก็บทั้งหมด / เก็บ 90 วันล่าสุด** | เป็นหลักฐาน compliance ผูกกับ **admin id** ไม่ใช่ test user → filter ราย user ไม่โดน แต่ full wipe จะทำลาย ต้องตัดสินใจชัด ๆ |
| **Q5** | staging เคยรับ **สลิปโอนเงินจริง** ผ่าน Slip2Go หรือไม่ | ถ้าเคย: ล้าง `payment.payment_slips` = ปลด UNIQUE `trans_ref`/`reference_id` → สลิปใบเดิมกลับมาจ่ายได้อีก |
| **Q6** | มี **CI / bot / integration ที่ใช้ `identity.api_tokens`** (`pguard_<prefix>_<secret>`) อยู่หรือเปล่า | ของ admin จะถูกเก็บไว้ตามแผน B แต่ของ non-admin จะหาย และ **plaintext กู้ไม่ได้** |
| **Q7** | `notification.broadcasts` มีแคมเปญ `status='scheduled'` ค้างอยู่ไหม → **เก็บหรือล้าง** | แผน B เก็บไว้ → มันจะยิงหา recipient ที่ถูกลบไปแล้ว อาจอยากล้างเฉพาะตารางนี้ |
| **Q8** | `booking.service_catalog` และ `profile.org_settings` ตอนนี้ **มีข้อมูลจริงที่กรอกไว้แล้วหรือยัง** (query ใน P0) | ถ้าว่างอยู่แล้ว การถกเรื่อง "ต้องเก็บ" ก็ตกไป และแผนง่ายขึ้น |
| **Q9** | หน้าต่างเวลาที่ยอมให้ **staging ดับ ~15 นาที** คือช่วงไหน และมีใครกำลังทดสอบอยู่ไหม | Option B ต้อง stop service ทั้งหมด |
| **Q10** | ยืนยันได้ไหมว่า **ไม่มีข้อมูลของลูกค้าจริง / รปภ. จริง** อยู่บน staging | ถ้ามี → เข้าข่าย PDPA ต้องทำ record การลบและแจ้งเจ้าของข้อมูล ไม่ใช่แค่ล้างเฉย ๆ |
| **Q11** | หลังล้างเสร็จ ต้องการ **seed ข้อมูลตั้งต้น** ไหม (แพ็กเกจราคา, org settings, บัญชีทดสอบชุดใหม่) | จะได้เตรียม checklist ต่อ — **หมายเหตุ: ห้ามใช้ `seed-v2.sql` บน staging** (เป็น synthetic perf data + รหัสสาธารณะ + UUID คงที่ที่ชนกับ `user_trv` marker) |

---

## 8. สิ่งที่ยังไม่แน่ใจ / ต้องยืนยันหน้างาน (ไม่เดา)

1. **สถานะ staging ปัจจุบัน** — ผมไม่ได้ SSH เข้าไปดู ตัวเลขทั้งหมด (จำนวน user, มี admin กี่คน, service_catalog ว่างหรือไม่, outbox ค้างกี่แถว) **ต้องรัน P0 ก่อน** ตัวเลขในเอกสารนี้เป็นโครงสร้างจากโค้ด ไม่ใช่จากฐานข้อมูลจริง
2. **Redis persistence** — compose ไม่ประกาศ named volume ให้ redis แต่ image `redis:7` ประกาศ `VOLUME /data` เอง → ผมเชื่อว่ามี anonymous volume ค้างข้ามการ recreate **แต่ยังไม่ได้ยืนยันบนเครื่องจริง** → ใช้ `FLUSHALL` ซึ่งถูกต้องทั้งสองกรณี
3. **NATS store เป็น ephemeral จริงไหม** — `nats.conf:34` ระบุว่า default/ephemeral store และ compose mount แค่ไฟล์ conf → `rm -sfv nats` ควรล้างครบ **แต่ควรยืนยันด้วย `docker inspect pguard-prod-nats --format '{{json .Mounts}}'` ก่อนรัน**
4. **จำนวน ledger 48 แถว** — นับจากไฟล์ในรีโปที่ branch ปัจจุบัน (`fix/qa-batch-jul21`) ส่วน staging ค้างอยู่ที่ commit `6d241a3` (ตามบันทึกเดิม) → **ตัวเลขจริงบน staging อาจน้อยกว่า** ต้องเทียบกับ `SELECT count(*) FROM public._perf_migrations` จริง ไม่ใช่ยึด 48
5. **`profile.access_audit` เชิงกฎหมาย** — ผมไม่ทราบข้อผูกพัน PDPA/สัญญาของโครงการ จึงตั้งเป็นคำถาม Q4 แทนการตัดสินใจให้
6. **pgbouncer** — Option B ใช้ `DELETE` ล้วน (ไม่เปลี่ยน OID) จึงไม่ควรเจอ `cached plan must not change result type` **แต่ถ้าเกิดขึ้นจริง แก้ด้วยการ restart service ที่ error** (นี่คือเหตุผลอีกข้อที่ปฏิเสธแนวทาง `DROP SCHEMA`)

---

## 9. บั๊กที่พบระหว่างวิเคราะห์ (ควรเปิด issue แยก ไม่เกี่ยวกับการล้างครั้งนี้)

1. `tooling/scripts/staging-delete-guard.sh` — ล้าง S3 แค่ 1 ใน 5 prefix, ไม่แตะ Redis เลย, และตกไป 6 ตาราง (`booking.guard_job_skips`, `notification.dispatch_recipients`, `identity.api_tokens`, `identity.totp_recovery_codes`, `chat.conversations`, outbox ทั้ง 7)
2. PDPA erase (`soft_delete_and_redact`) **ไม่ลบไฟล์ใน S3 เลย** — บัตร ปชช. ของ user ที่ "ลบแล้ว" ยังอยู่ในถังตลอดกาล (§33 gap จริง)
3. `user_trv:{user_id}` ใน Redis **ไม่มี TTL และไม่มี cleanup path** → leak ถาวร
4. stream `PGUARD_EVENTS` **ไม่มี `max_age` / `max_msgs`** → เก็บทุก event ตลอดกาลใน container ที่ไม่มี volume
5. `presence-booking-links` และ `profile-booking-links` **ไม่มี `processed_events` ledger** → durable reset = ปลุกแถวที่ลบไปแล้วคืนชีพ
6. `mark_paid_idempotent` (`booking/repo/mod.rs:1281`) claim event สำเร็จแล้ว `UPDATE` โดน 0 แถว แต่ยัง `COMMIT` + return `Ok(true)` → log ว่า "booking marked paid" ของ booking ที่ไม่มีอยู่
7. web-admin: หน้า login ส่งรหัสดิบ / หน้า Profile ส่ง SHA-256 → **ไม่มี encoding เดียวที่ทั้งสอง flow ทำงานได้** (ล็อกตัวเองออกจากระบบได้จริง)
8. web-admin: เปิด 2FA แล้ว login เด้งวนลูป (`POST /auth/2fa/verify` มี route + generated client แต่ไม่มีที่เรียกใน `app/`)

---

### ขั้นตอนถัดไป
ตอบ **Q1–Q11** (โดยเฉพาะ Q1 ที่ต้องรัน query P0 บน VPS ก่อน) แล้วผมจะแปลง Option B เป็นสคริปต์เดียว `tooling/scripts/staging-reset.sh` ที่มี dry-run, ยืนยันสองชั้น, ตรวจ outbox อัตโนมัติ, และ verification block ในตัว

**ไฟล์อ้างอิงหลัก (absolute paths):**
`/Users/nest/Documents/pguard/tooling/scripts/staging-delete-guard.sh` ·
`/Users/nest/Documents/pguard/tooling/scripts/migrate.sh` ·
`/Users/nest/Documents/pguard/tooling/scripts/deploy-staging.sh` ·
`/Users/nest/Documents/pguard/contracts/db/migrations/` (48 ไฟล์ / 10 schema / 46 ตาราง) ·
`/Users/nest/Documents/pguard/infra/docker/docker-compose.prod.yml` + `docker-compose.staging.yml` ·
`/Users/nest/Documents/pguard/infra/docker/nats.conf` ·
`/Users/nest/Documents/pguard/v1-audit/perf-baseline/scripts/seed-v2.sql` (**ห้ามรันบน staging**)