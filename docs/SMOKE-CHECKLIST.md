# Smoke Test Checklist — staging `pguard.innoveraappcenter.com` (2026-06-11)

> กดตามทีละข้อ ติ๊ก ✅/❌ + จดอาการถ้า fail — เจออะไรส่งให้ Cowork เปิด finding
> **อย่าข้ามข้อ Prep** ไม่งั้นไปตันกลางทาง

## 0. Prep

- [ ] **Admin user** มีใน identity (`role='admin'`) — login web-admin ได้
- [ ] **SMS เปิดจริง** (`SMS_DISABLED=false` + INET creds — ทำไปแล้ว ✅)
- [ ] **มือถือจริง 2 เครื่อง** (หรือเครื่อง+emulator): เครื่อง A = customer, เครื่อง B = guard
  — build: `flutter run --dart-define=PGUARD_API_HOST=https://pguard.innoveraappcenter.com`
  (ชื่อ define ตรวจแล้วจาก `lib/core/config/app_config.dart`; WS/media host จะ derive จาก api host เว้นแต่ override ด้วย `PGUARD_WS_HOST`/`PGUARD_MEDIA_HOST`)
- [ ] **Redeploy main ปัจจุบันก่อน** (มี #36/#41/#43–#47 ใหม่หมด): VPS `git pull` → **เติม `NATS_*_PASSWORD` 11 ตัวใน `infra/.env.staging`** (PR #36 — ไม่เติม = stack boot ไม่ขึ้น; gen ด้วย `openssl rand -hex 24` ค่าต่างกันทุกตัว) → `docker compose pull` (image build อัตโนมัติจาก main push แล้ว) → up
- [ ] หลัง up: ทุก service ต่อ NATS ได้ (log ไม่มี `authorization violation`) + gateway `/readyz` = 200 (ภายใน network)
- [ ] VPS: `docker ps` healthy ครบ · Grafana เปิดดูได้ (สำหรับข้อ 7)

## 1. Registration + OTP (เครื่อง B — guard ก่อน เพราะต้องรอ approve)

- [ ] สมัคร role=guard: เบอร์จริง → **จอ captcha (บวกเลข) คั่นก่อนส่ง OTP** (#43) → ได้ SMS OTP → กรอก → ตั้ง PIN + **ยืนยัน PIN ซ้ำ** (#46) — สังเกตฟอนต์ IBM Plex Thai + logo จริงทุกจอ
- [ ] กรอก profile guard (รูป, เอกสาร, บัญชีธนาคาร) → จอ **pendingApproval**
- [ ] ยัง login ไม่ได้ระหว่าง pending (ต้องโดนปฏิเสธแบบ generic ไม่บอกเหตุผล)
- [ ] เครื่อง A สมัคร role=customer ด้วยเบอร์ที่สอง → ใช้งานได้เลย

## 2. Web-admin (desktop)

- [ ] Login (httpOnly cookie — token ต้องไม่อยู่ใน devtools document.cookie)
- [ ] Dashboard ตัวเลขขึ้น (pending applicants ต้องเห็น guard จากข้อ 1)
- [ ] **Approve guard** → เครื่อง B login ได้ภายใน ~วินาที (event loop:
  profile→NATS→identity — จุดพิสูจน์ NATS ACL บน staging)
- [ ] Reviews: toggle visibility + persist ข้าม reload
- [ ] Map: เปิดได้ (guard online จะเห็นหลังข้อ 3)
- [ ] Settings: เปลี่ยนภาษา TH/EN + logout/login ใหม่

## 3. Guard online + discovery (เครื่อง B)

- [ ] Login → toggle **online** → GPS uplink ติด (สถานะ link = online)
- [ ] Web-admin Map เห็น guard โผล่ตำแหน่งจริง
- [ ] จอ open-jobs ยังว่าง (ยังไม่มี booking)

## 4. Booking flow (เครื่อง A จอง → เครื่อง B รับ)

- [ ] Customer สร้าง booking (เลือกพิกัด+ชั่วโมง) → จ่าย (simulated) → สถานะ requested
- [ ] Guard เห็นงานใน **open jobs** (discovery จาก PR #27) → กดรับ
- [ ] Customer เห็นสถานะเปลี่ยนเป็น accepted **แบบ realtime ไม่ต้อง refresh** (WS push)
- [ ] Guard กด en-route → arrived → start work — customer เห็นทุก step สด
- [ ] **Live-map**: customer เปิดแผนที่จาก live status → เห็น marker guard + ระยะห่าง
  + freshness (จุดพิสูจน์ presence ผ่าน edge จาก PR #25+#26)

## 5. ระหว่างงาน (จุดพิสูจน์หนักสุด)

- [ ] **Check-in ชั่วโมงที่ 1** (เครื่อง B): ถ่ายรูปจริงจากกล้อง → ส่งสำเร็จ
  (พิสูจน์ #27+#28 body-cap+#29+#30 ทั้งสาย) → กดส่งซ้ำ = ไม่ error (409 absorbed)
- [ ] **Chat**: ส่งข้อความสองทาง realtime + **ส่งรูป** (attachment ผ่าน edge —
  พิสูจน์ body-cap) + unread badge ขึ้นที่ entry
- [ ] **Call**: voice call ระหว่างสองเครื่อง — ต่อติด ได้ยินเสียง (ทดสอบบน
  **เน็ตมือถือ** อย่างน้อยฝั่งเดียว เพื่อพิสูจน์ TURN relay ไม่ใช่แค่ LAN)
- [ ] Notification centre มีรายการ event ที่ผ่านมา

## 5.5 จอใหม่จาก design pass (#46 + แท็บใหม่)

- [ ] **Bottom nav**: เครื่อง A เห็น FAB เหลือง "เรียก รปภ." กลางแถบล่าง → กดเข้า flow จอง · เครื่อง B เห็น duty-FAB (เปิด/ปิดรับงาน) + badge เลขงานเข้าที่แท็บ "งาน"
- [ ] **แท็บ การจอง** (A): list การจองของตัวเอง สถานะถูกต้อง กดเข้า live status ได้
- [ ] **แท็บ กระเป๋า** (A): รายการจ่ายเงิน + ยอดรวมตรงกับที่จ่ายจริง
- [ ] **แท็บ รายได้** (B): งานที่จบแล้วขึ้น + ยอดรวมสมเหตุผล (ป้าย "ประมาณการ" ถ้ามี)
- [ ] **ยกเลิกการจอง** (A, ทำกับ booking ที่ยัง pre-arrival): ปุ่มยกเลิกใน live status → จอเหตุผล 4 ข้อ + refund banner → confirm sheet → ยืนยัน → สถานะ cancelled ขึ้น **realtime** ทั้งสองเครื่อง; หลัง guard กด arrived ปุ่มยกเลิกต้อง**หาย**
- [ ] **ถอนงาน guard** (B, งานที่รับแล้วยัง pre-arrival): จอถอนงาน (warning escalation + เหตุผล + note) → ส่ง → กลับ dashboard, customer เห็นสถานะเปลี่ยน
- [ ] **Error+retry**: ปิด wifi ชั่วคราวแล้วเปิดจอ list ใดๆ → เห็น error state ดีไซน์ใหม่ + ปุ่ม "ลองอีกครั้ง" ใช้ได้

## 5.6 Web-admin จอใหม่ (rebuild pass)

- [ ] Shell ใหม่: sidebar 4 กลุ่ม + active เข้ม + dark mode toggle ที่ foot ใช้ได้ (สลับแล้วจอไม่พัง)
- [ ] Dashboard: KPI ที่มีข้อมูลจริงขึ้นเลข (ผู้สมัคร/ออนไลน์/รีวิว) · ช่องที่ติด API gap มีป้ายบอกชัด ไม่มีเลขปลอม
- [ ] Login ใหม่ render ถูก + login ได้เหมือนเดิม
- [ ] จอ applicants/guards/reviews/map ใช้งานเดิมได้ครบ (approve/reject · ดูบัญชี masked · toggle รีวิว · แผนที่)

## 6. จบงาน

- [ ] Guard complete งาน → customer เห็น completed + ใบเสร็จ/ยอด
- [ ] Customer ให้คะแนน review → ขึ้นใน web-admin reviews
- [ ] Chat ของ booking ที่จบ → composer เป็น read-only

## 7. Infra spot-checks (VPS / browser)

- [ ] Grafana: dashboards 3 ตัวมีข้อมูลวิ่งระหว่าง smoke (overview + edge + NATS)
- [ ] `docker logs pguard-prod-nats --since 30m | grep -ci 'authorization violation'` = 0
- [ ] Redis restart รอบสอง (ยืนยัน reconnect ซ้ำหลังมี traffic จริง):
  `docker restart pguard-prod-redis && sleep 8 && curl -sk -o /dev/null -w '%{http_code}\n' https://pguard.innoveraappcenter.com/v1/locations` → 401
- [ ] `/readyz` ผ่าน nginx ไม่ expose (เช็ค `curl -sk https://pguard.innoveraappcenter.com/readyz` → ควร 404/444 ที่ edge — readyz ไว้ใช้ภายใน)

## 8. Negative cases (เร็วๆ)

- [ ] OTP ผิด 5 ครั้ง → โดน lock ตาม max-attempts
- [ ] ยิง OTP รัว → เจอ rate limit (ที่เจอตอน debug — by design)
- [ ] Login ผิดรหัส → generic error ไม่บอกว่าเบอร์มีจริงไหม
- [ ] เปิด `https://…/v1/admin/reviews` ไม่มี token → 401

---
**ถ้า fail:** จดข้อ + screenshot/log → ส่ง Cowork → ผมจะ triage เป็น finding/slice
**ผ่านหมด:** staging = demo-ready · เหลือกลุ่มที่พักไว้ (payment จริง · terraform · mobile dark mode · admin aggregate endpoints)
