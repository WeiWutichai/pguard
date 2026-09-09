# PHASE — Bank export: 3 money streams (ไฟล์โอนธนาคาร 3 ส่วน)

> ⚠️ **สถานะเอกสาร (อัปเดต 2026-09-07) — §1–§3 คือ "บันทึกก่อนลงมือ" ไม่ใช่สภาพปัจจุบัน**
>
> เอกสารนี้เขียน**ก่อนเริ่มงาน** เป็นผลสำรวจ + แผน ทุกประโยคในส่วนสำรวจจึงหมายถึง "ตอนนั้น"
> **แผน P0–P4 ทำเสร็จแล้วบน branch `feat/bank-export-3-streams`** — ตอนนี้ออกไฟล์ได้**ครบทั้ง 3 stream**
> (`cargo test --workspace` เขียว 1,333 · web-admin lint/typecheck/build เขียว)
>
> | ส่วน | อ่านยังไง |
> |---|---|
> | §0 สรุปผู้บริหาร | ✅ อัปเดตแล้ว — คอลัมน์ขวาสุดคือของที่ส่งมอบจริง |
> | **§1 · §2 · §3 (ผลสำรวจ)** | 🕰️ **ประวัติ — เก็บไว้ครบตามเดิม ห้ามลบ** เพราะคือคำอธิบายว่า *อะไรพัง เพราะอะไร* = เหตุผลของทั้ง diff (reviewer ต้องใช้ตัดสิน) |
> | §4 แผน dev | ✅ อัปเดตแล้ว — เลข migration จริง + จุดที่ **ทำต่างจากแผน** พร้อมเหตุผล |
> | §5 การตัดสินใจ | ✅ อัปเดตแล้ว — ทวนทุกแถวกับโค้ดจริงเมื่อ 2026-09-07 |
>
> สถานะระดับ task (รวมของที่ยัง**ไม่**ได้ทำ) อยู่ที่ `PROGRESS.md` หัวข้อ 🏦 Bank export

---

> **สำรวจแล้ว (2026-09-07 · ก่อนเริ่มงาน — แก้แล้วทั้งหมด ดู §0):** ระบบ export ไปธนาคาร
> **ยังไม่ครบ และยังใช้งานจริงไม่ได้** เขียนไปแล้ว 1 ใน 3 stream — แต่ **ใช้งานได้จริง 0 ใน 3**
>
> วิธีตรวจ: 6-area survey + adversarial verify (104 agents) → **89 gaps confirmed / 6 refuted**
> ข้อสรุปทุกข้อในเอกสารนี้ verify กับโค้ดจริง + `docs/reviews/CPX_Toolkit_Reverse_Engineering.md` แล้ว

---

## 0. สรุปผู้บริหาร

| # | Stream | ที่ควรเป็น | สถานะ**ตอนสำรวจ** (ก่อนงานนี้) | **ส่งมอบแล้ว** (branch นี้) |
|---|---|---|---|---|
| 1 | **ยอดที่ต้องโอนคืนคนจ้าง** (refund → customer) | ไฟล์ธนาคาร | ❌ **ไม่มีเลย** — มีแต่คิวอ่านอย่างเดียวที่ระบายไม่ได้ | ✅ ไฟล์ `PPY` + `/admin/refunds/preview\|export` + lifecycle/void · mig `0011` · หน้า `/refunds` (P3) |
| 2 | **ยอดที่โดนหักเข้าระบบ** (platform cut) | **ไฟล์ SCB แยกใบ (product `OAT`)** + รายงานภาษี | ❌ **ไม่มีตัวเลขนี้อยู่ในระบบเลย** | ✅ `settlement::split()` + snapshot ราคา (mig `0013`) → `/admin/deductions/preview\|export` (`OAT`) + 2 รายงานภาษี + หน้า `/deductions` (P4) |
| 3 | **ยอดที่โอนให้ รปภ** (guard payout) | ไฟล์ธนาคาร | ⚠️ **เขียนครบ แต่วันนี้จ่ายใครไม่ได้สักคน** | ✅ กรอก `tax_id` ได้ (`PUT /admin/guard-profiles/{id}/payout`) + ไฟล์ผ่านสเปค F1–F8 + batch lifecycle/void (P0–P2) |

**ประโยคเดียว (ตอนสำรวจ):** stream 3 เขียนเสร็จแต่ 400 ทุกครั้งเพราะไม่มีที่ไหนกรอกเลขบัตร ปชช. รปภ. ได้เลย,
stream 1 ไม่มีปลายทางให้โอนคืน, stream 2 ยังไม่มีตัวเลขให้ export

**ประโยคเดียว (ตอนนี้):** ทั้งสาม stream ออกไฟล์ SCB ได้จริง **แยกใบต่อ product** เก็บไฟล์ไว้ดาวน์โหลดซ้ำได้
มี status/void ที่คืนงานเข้าคิวได้ และมี `money_audit` บันทึกทุก action ที่ขยับเงิน

> **ยังไม่ทำ (ยกเป็นหนี้ทางเทคนิค — ตรงกับ `PROGRESS.md`):** P5 reconciliation/import ผลจากธนาคาร ·
> แจ้งเตือน รปภ. เมื่อเงินโอนแล้ว · Dart client (payment + profile) ยัง stale · เก็บ `tax_id`
> ตอนสมัครในแอป (วันนี้ admin กรอกให้) · 3 บั๊กเชิงธุรกิจใน §1.4 (ทิป · `guard_count` · งานที่ถูกยกเลิก)

### 🔒 ที่ผู้ใช้ตัดสินใจแล้ว (2026-09-07)

| # | เรื่อง | คำตอบ |
|---|---|---|
| — | ช่องทางโอน | **ทุกรายการโอนผ่าน SCB Business Net ทั้งหมด** |
| — | โครงสร้างไฟล์ | **แยกไฟล์ต่อหัวข้อ** — ห้ามรวมสามส่วนไว้ในไฟล์เดียว (ตรงกับข้อจำกัดของ SCB เอง: 1 `BCHDET` = 1 `productCode`) |
| 1 | ปลายทางคืนเงินลูกค้า | ใช้ข้อมูลที่เก็บไว้ตอน**ลงทะเบียน** (เบอร์ที่สมัคร → พร้อมเพย์ MOB) — ไม่ขอข้อมูลใหม่จากลูกค้า |
| 5 | ยอดหักเข้าระบบ | **ออกไฟล์ SCB ด้วย** → เป็น product `OAT` โอนจากบัญชีรับเงินลูกค้าเข้าบัญชีรายได้บริษัท |
| 2/3 | ทิป · `guard_count` | **ยังไม่แก้ตอนนี้** — บันทึกไว้เป็นหนี้ทางเทคนิค |
| 6 | เพดานยอดต่อรายการ | **ตอบได้จากเอกสารแล้ว** — ดู §3.1 ด้านล่าง |
| — | ลำดับงาน | เริ่มที่ **P0 + P1** |

### เพดานยอดพร้อมเพย์ — ข้อขัดแย้งในเอกสารคลี่แล้ว

เอกสารดูขัดกันเองระหว่าง §15.10 (฿10,000) กับบรรทัด 409 (฿2,000,000) — คำตอบอยู่ที่ **§7.4**:
SCB stamp ชนิด proxy จาก**ความยาว** แล้ว §7.5 เลือก validator ตามนั้น

| ความยาว proxy | ชนิด | เพดานต่อรายการ |
|---|---|---|
| 15 หลัก | `EWL` (e-wallet) | **฿10,000** |
| 13 หลัก | `NAT` (เลขบัตร ปชช.) | **฿2,000,000** |
| 10 หลัก | `MOB` (เบอร์มือถือ) | **฿2,000,000** |

รปภ. ใช้ `NAT`/`MOB` และลูกค้าใช้ `MOB` → **เพดานคือ ฿2,000,000** ทั้งคู่ ฿10,000 ไม่เกี่ยวเลย

---

## 1. Stream 3 — ยอดที่โอนให้ รปภ (เขียนแล้ว แต่จ่ายไม่ได้)

> 🕰️ **ประวัติ — สภาพ ณ 2026-09-07 ก่อนลงมือ.** A/B/C แก้ใน **P0**, F1–F8 แก้ใน **P1**,
> §1.3 (ประตูทางเดียว) ปิดใน **P2** — เก็บไว้ครบเพราะเป็นเหตุผลของทุกบรรทัดใน diff
> §1.4 **ยัง open จริง** (รอผู้ใช้ตัดสิน — ดู §5 ข้อ 2/3)

### 1.1 สาม hard stop ที่ทำให้ export คืนค่า 400 เสมอ

| # | ปัญหา | หลักฐาน |
|---|---|---|
| A | **ไม่มี UI/API ใดกรอก `tax_id` ของ รปภ. ได้เลย** — mobile registration ไม่ส่ง, `PUT /profile/guard` ไม่เขียนคอลัมน์นี้, ไม่มี admin write route | `services/profile/src/repo/mod.rs:436-449` · `services/profile/src/main.rs:191-292` |
| B | **upsert ล้าง `tax_id` ทิ้ง** — `tax_id = EXCLUDED.tax_id` ไม่มี `COALESCE` → รปภ. กดบันทึกโปรไฟล์ (ไม่ส่ง key นี้) = ค่าที่เคยใส่หายทันที + ไม่มี validation | `services/profile/src/repo/mod.rs:402` |
| C | **`phone: None` hardcode** → MOB fallback เป็น dead code | `services/profile/src/api/mod.rs:1509-1511` |

ผลรวม: ด้วย `wht_rate_percent = 3` (ค่า default) **ทุก** รปภ. ตกเข้า exclusion branch
(`services/payment/src/api/payouts.rs:213-217`) → `POST /admin/payouts/export`
คืน `400 "ไม่มีรายการค้างจ่ายที่จ่ายได้ในขณะนี้"`

### 1.2 ไฟล์ที่สร้างออกมา "ผิดสเปค" — ต่อให้ใส่ tax_id ด้วย SQL ตรงๆ ธนาคารก็ตีกลับ

| # | ปัญหา | สเปค | โค้ดตอนนี้ |
|---|---|---|---|
| F1 | **`WHTDET` ต้องเป็น record แยกบรรทัด** — เอกสารระบุว่านี่คือ *"the single most important structural fact"* | `WHTCER\|…19` แล้วขึ้นบรรทัดใหม่ `WHTDET\|…7` (doc:2283-2284, 2592) | ต่อท้ายเป็นบรรทัดเดียว 26 ฟิลด์ + field 0 ของ detail เขียน `"1"` แทน `"WHTDET"` (`scb_export.rs:238-262`) |
| F2 | **Customer Batch Ref ยาวเกิน** | ≤ 12 ตัวอักษร (doc:405, 736) | `<DDMMYYHHMMSS>PPY` = **15 ตัว** → ตกที่ batch header ก่อนอ่าน transaction |
| F3 | **batchRef / fileRef สลับกัน** | `fileRef = batchRef & productCode` (doc:1420) | `file_ref` เขียนเป็น *ชื่อไฟล์* `SCB_file_reference_…` (`payouts.rs`) |
| F4 | **value_date ใช้ UTC** | ห้ามย้อนหลัง + ต้องเป็นวันทำการ (doc §15.11) | `Utc::now().date_naive()` → รัน 00:00–07:00 น. ไทย = ได้วัน**เมื่อวาน** → reject; ไม่มี business-day guard |
| F5 | **ไม่ normalize เป็นตัวเลข** | credit account ต้องเป็นตัวเลขล้วน 10–15 หลัก | `classify_proxy` ตัด `-` ก่อนเช็ค แต่ **เขียนค่าดิบ** ลงไฟล์ → `1-2345-67890-12-3` (profile อนุญาตให้ใส่ขีด) หลุดเข้าไฟล์ |
| F6 | **ไม่ escape `\|`** | ไฟล์เป็น positional pipe-delimited | ชื่อ/ที่อยู่/ชื่อบริษัท เป็น free text — `\|` ตัวเดียวเลื่อนทุกฟิลด์ถัดไป เงียบๆ |
| F7 | **ไม่เช็คเพดานยอดต่อรายการ** | **฿2,000,000** สำหรับ proxy `NAT`/`MOB` (฿10,000 เป็นเพดานของ `EWL` เท่านั้น — คลี่จาก §7.4/§7.5 แล้ว) | ไม่เช็คเลย |
| F8 | **ฟอร์ม ภ.ง.ด. default ผิด** | proxy เป็นเลขบัตร ปชช. = บุคคลธรรมดา → **ภ.ง.ด.3 (`04`)** | default `'53'` = นิติบุคคล (`0007_guard_payout.sql`) |

### 1.3 ประตูทางเดียว — ไม่มีทางย้อนกลับ

- **mark paid ก่อนธนาคารรับ**: `repo::insert_payout_batch` commit paid-marker **เสร็จก่อน** ส่ง body ออก
  (`payouts.rs:459-487`) → ถ้า download หลุด/ปิดแท็บ/proxy timeout = งานถูกมาร์กว่าจ่ายแล้วถาวร แต่เงินไม่เคยออก
- **ไฟล์ไม่ถูกเก็บที่ไหนเลย** — ไม่มี S3, ไม่มีคอลัมน์ใน DB, สร้างครั้งเดียวแล้วหาย
- **ไม่มี batch history / re-download** — `payout_batches` เขียนแล้วไม่มีใครอ่าน (write-only)
- **ไม่มี void / un-mark** — ธนาคารตีกลับ = ต้อง `DELETE` มือใน production
- **ไม่มี status** — `payout_batches` มีสถานะเดียวคือ "มีอยู่"; ระหว่าง generated → uploaded → confirmed → rejected ไม่ถูก model เลย

### 1.4 บั๊กเชิงธุรกิจที่โผล่มาระหว่างสำรวจ (ต้องให้ผู้ใช้ตัดสินใจ)

| # | เรื่อง | สภาพตอนนี้ |
|---|---|---|
| B1 | **ทิป** | ลูกค้าถูกเก็บเงินค่าทิป (`pricing.rs` subtotal) แต่ payout ไม่รวมทิปเลย → **แพลตฟอร์มเก็บทิป 100%** |
| B2 | **`guard_count`** | คิดเงินลูกค้าได้ถึง 20 คน แต่ `booking.bookings` มี `guard_id` เดียว → จ่าย รปภ. ได้คนเดียว ที่เหลือกลายเป็นรายได้แพลตฟอร์มเงียบๆ |
| B3 | **งานที่ถูกยกเลิก** | รปภ. ที่ออกเดินทางแล้วโดนยกเลิก ได้ 0 บาท (row กลายเป็น `refunded` แล้วหลุดออกจาก backlog) |

---

## 2. Stream 1 — ยอดที่ต้องโอนคืนคนจ้าง (ไม่มีเลย)

> 🕰️ **ประวัติ — สภาพ ณ 2026-09-07 ก่อนลงมือ.** R1–R5 แก้ใน **P3** (R1 แก้แบบไม่เก็บ PII ใหม่:
> `contact_phone` → fallback เบอร์ login) · **R6 ไม่ต้องแก้** — payment ไม่ได้ขอ `IDENTITY_URL`
> เพราะ profile เป็นคนคุยกับ identity ให้ใน `/internal/customers/{id}/payout-profile`
> §2.1 (4 ทางที่เงินค้าง) **ยังจริงอยู่** — เป็น input ของ backlog ที่ P3 สร้าง

### 2.1 เงินที่ค้างคืนลูกค้ามาจาก 4 ทาง

| แหล่ง | เก็บที่ | สถานะ workflow |
|---|---|---|
| prorate ตอนจบงาน (จ่ายเกินชั่วโมงจริง) | `payments.refund_amount` | `refund_status='pending'` |
| ยกเลิกงาน (เต็ม/หักค่ายกเลิก) | `payments.refund_amount` (+ `overpaid_amount`) | `refund_status='pending'` |
| แพ้ race ตอน pre-pay | `payments.refund_amount` | `refund_status='pending'` |
| **สลิปโอนซ้ำ** (โอนจริง 2 ครั้ง) | `payment_slips.applied=FALSE` | `payment_slips.refund_status='pending'` |

### 2.2 ทำไมถึงคืนเงินไม่ได้

| # | ปัญหา | หลักฐาน |
|---|---|---|
| R1 | **ลูกค้าไม่มีปลายทางรับเงินเลย** — `customer_profiles` มีแค่ `full_name, address, company_name, email, contact_phone, approval_status, avatar_key` ไม่มี bank/account/พร้อมเพย์/เลขบัตร | ทั้ง 15 migration ของ profile |
| R2 | **ไม่มีโค้ดไหนเขียน `refund_status='processed'` เลย** — เขียนแต่ `'pending'` 3 จุด | `repo/mod.rs:962, :1166, :1245` |
| R3 | **ไม่มี paid-marker** — schema `payment` มี 7 ตาราง ไม่มีตารางฝั่ง refund เลย → export 2 รอบ = **คืนเงินซ้ำ** |
| R4 | **ไม่มี endpoint** `/admin/refunds/preview` และ `/admin/refunds/export` — route refund มีอันเดียวคือ GET queue | `services/payment/src/main.rs` |
| R5 | **ไม่มี `/internal/customers/{id}/payout-profile`** — payment อ่านข้อมูลลูกค้าไม่ได้ตามกติกา per-service ownership | `services/profile/src/main.rs:268-292` |
| R6 | **payment ไม่มี `IDENTITY_URL`** — เบอร์โทรลูกค้า (MOB proxy ที่เป็นไปได้มากสุด) อยู่ที่ identity แต่เอื้อมไม่ถึง | มีแค่ `BOOKING_URL` + `PROFILE_URL` |

หน้า `/wallet` เขียนโน้ตไว้ตรงๆ ว่า *"v2 refunds are automatic / event-driven"* — แต่จริงๆ
**ไม่มีอะไรอัตโนมัติ** เงินไม่เคยออกจากบัญชี ลูกค้าได้แค่ push แจ้งว่า "กำลังคืนเงิน"

---

## 3. Stream 2 — ยอดที่โดนหักเข้าระบบ

### 3.1 ผู้ใช้เลือกให้ **ออกไฟล์ SCB** (แก้จากร่างแรก)

ร่างแรกสรุปว่าส่วนนี้ควรเป็นรายงาน เพราะเงินไม่เคยเคลื่อนย้าย — ผู้ใช้ยืนยันให้**โอนจริง** คือ
sweep ยอดหักออกจากบัญชีที่รับเงินลูกค้า เข้า**บัญชีรายได้ของบริษัท** ซึ่งเป็น practice ปกติทางบัญชี
(แยกเงินลูกค้าออกจากเงินบริษัทให้ชัด)

**แปลว่า:** product = **`OAT` (own-account transfer)** ไม่ใช่ `PPY` → ต้องทำ writer ให้แตกตาม product ก่อน
ข้อกำหนดของ `OAT` จากเอกสาร §7.2 / §7.4:

| ฟิลด์ | ค่า |
|---|---|
| `TXNDET` f3 (proxy type) | ว่าง |
| `TXNDET` f4 (bank code) | รหัสธนาคาร 3 หลัก zero-pad (`014` = ไทยพาณิชย์) |
| `TXNDET` f5 (branch) | `"0111"` |
| `TXNDET` f7 (service type) | รหัส service type |
| เลขบัญชีปลายทาง | ต้องเป็นบัญชี SCB **10 หลักพอดี** + ผ่าน check-digit (§14 `CheckScbDigit`) |

และยังต้องมีอีก **2 อย่างที่เป็นเงินออกจริงไปสรรพากร** (ยื่นผ่าน e-filing ไม่ใช่ไฟล์โอน):

| รายการ | เป็นอะไร | กำหนด |
|---|---|---|
| **VAT 7%** | เก็บแทนสรรพากร → ต้องนำส่ง | **ภ.พ.30** รายเดือน |
| **WHT 3% ที่หักจาก รปภ.** | หักไว้แล้ว ต้องนำส่ง | **ภ.ง.ด.3/53 ภายในวันที่ 7 ของเดือนถัดไป** |

### 3.2 ปัญหา

> 🕰️ **ประวัติ — สภาพ ณ 2026-09-07 ก่อนลงมือ.** P1–P6 แก้ใน **P4**: mig `0013` snapshot
> `base_fee`/`booked_hours`/`guard_count`/`tip`/**`commission_amount` (บาท)** ลง `payment.payments`
> (ปิด P2/P3) → `domain::settlement::split()` + invariant (ปิด P1/P4) →
> `/admin/reports/wht-payees` อ่าน `payout_batch_items.wht` ที่เคย write-only (ปิด P5) +
> `/admin/reports/vat-register` (ปิด P6)

| # | ปัญหา | หลักฐาน |
|---|---|---|
| P1 | **ไม่มีตัวเลข "ยอดหัก" อยู่ในระบบเลย** — `NET_REVENUE_EXPR` คือ**รายได้รวมที่ยังไม่หักค่าแรง รปภ.** เอาไปแสดงเป็น "ยอดหักเข้าระบบ" จะ**เกินจริง 80–95%** ของทุกงาน | `repo/mod.rs` NET_REVENUE_EXPR |
| P2 | **commission เก็บแค่ %** ไม่เก็บจำนวนเงินบาท → องค์ประกอบใหญ่สุดของยอดหักอ่านจาก DB ไม่ได้ | `0005_vat_and_fees.sql` |
| P3 | **`base_fee` / hours / guard_count / tip ไม่อยู่ใน schema payment** → ทุกรายงานต้อง HTTP fan-out ไป booking (N+1) และ export ย้อนหลังทำซ้ำให้เหมือนเดิมไม่ได้ |
| P4 | **ไม่มี settlement ledger** — ไม่มีอะไรยืนยันว่า `ลูกค้าจ่าย = โอน รปภ + commission + VAT + WHT + ค่ายกเลิก + คืนเงิน` |
| P5 | **`payout_batch_items.wht` เขียนแล้วอ่านไม่ได้** — ตัวเลขที่กฎหมายบังคับให้รายงาน ไม่มี endpoint ไหนอ่าน |
| P6 | **ไม่มีรายงานภาษีขาย (ภ.พ.30) และไม่มีรายงาน ภ.ง.ด. payee** |

---

## 4. แผน Dev (5 phase — เรียงตามลำดับที่ต้องทำ)

> หลักการ: **ทำให้จ่ายได้ก่อน → ทำให้ไฟล์ถูกสเปค → ปิดประตูทางเดียว → เพิ่ม stream 1 → เพิ่มรายงาน stream 2**
> Phase 0/1 คือของที่ต้องทำอยู่แล้วไม่ว่าจะตัดสินใจเรื่อง stream 1 อย่างไร — เริ่มได้ทันที

> ✅ **ทำจริงแล้ว P0 → P4 (2026-09-07).** ตารางในแต่ละ phase คือ**แผน**ที่เขียนไว้ตอนต้น —
> ที่ทำจริงต่างจากแผนตรงไหนมีหมายเหตุกำกับไว้ในแต่ละ phase แล้ว

### เลข migration ที่ใช้จริง (payment) — **แผนเดิมเขียนเลขผิดทุกตัว**

แผนแรกจอง `0008` (P2) · `0009` refund batches (P3) · `0010` pricing snapshot (P4) แต่ P1 กินเลข
`0008` ไปก่อน แล้วรอบ review ยังงอกอีก 2 ตัวที่ไม่มีในแผนเลย ของจริงคือ
(ตรวจกับ `ls contracts/db/migrations/payment/` + หัวไฟล์แต่ละใบ 2026-09-07):

| ไฟล์ | เนื้อหา | มาจาก |
|---|---|---|
| `0008_payout_txn_cap.sql` | `max_transfer_per_txn` เพดานต่อรายการ (คลี่ ฿10,000 vs ฿2,000,000) | P1 |
| `0009_payout_batch_lifecycle.sql` | `status` + `file_text` + `voided_*` + `voided_at` บน **item** + partial unique + `money_audit` + แก้ `recipient_count` | P2 |
| `0010_payout_config_and_batch_refs.sql` | `fee_charge_code` (§5 ข้อ 7) · `sms_notify` opt-in · `uq_payout_batches_file_ref` | P2 (review) |
| `0011_refund_batches.sql` | `refund_batches` + `refund_batch_items` (paid-marker composite 2 lane) | P3 |
| `0012_scb_file_refs.sql` | **ไม่มีในแผน** — จองเลขอ้างอิง SCB ร่วมทั้ง 3 stream | P3 (review) |
| `0013_platform_cut_sweep.sql` | snapshot ราคา + `commission_amount` (บาท) + `deduction_batches`/`_items` | P4 |
| `0014_deduction_uncollected.sql` | **ไม่มีในแผน** — `uncollected` + CHECK ใหม่ (ห้าม sweep เงินที่ยังเก็บไม่ได้) | P4 (review) |

**`0012` กับ `0014` เกิดจากรอบ review ที่แผนเดิมคาดไม่ถึง** และทั้งคู่เป็นบั๊กเงินจริง:
`0012` — refund กับ payout ขี่ `PPY` เหมือนกัน ออกไฟล์ในวินาทีเดียวกัน = `batch_ref`/`file_ref` ชนกัน
ข้าม stream ซึ่ง unique ต่อตารางมองไม่เห็น · `0014` — งานที่ reconcile ออกมา**สูงกว่า**ยอด pre-pay
มีส่วนต่างที่ไม่เคยเก็บเงินจริง แต่ sweep เดิมโอนเข้าบัญชีรายได้ไปแล้ว = ดูดเงิน VAT/ค่าแรงที่ไม่ใช่ของบริษัท
ต่อไปเริ่มที่ `0015`

### Phase 0 — ทำให้ รปภ. จ่ายได้จริง (ปลดล็อกของที่เขียนไปแล้ว)

| งาน | ไฟล์ |
|---|---|
| `validate_tax_id` กับ tax_id ของ รปภ. + เปลี่ยน upsert เป็น `COALESCE` (เลิกล้างทิ้ง) + ให้ `PUT /profile/guard` เขียนคอลัมน์นี้ | `services/profile/src/repo/mod.rs:402,436-449` · `api/mod.rs` |
| เพิ่ม admin write endpoint สำหรับ payout fields ของ รปภ. (tax_id / bank) + เขียน PDPA access_audit | `services/profile/src/main.rs` · `api/mod.rs` · `contracts/openapi/profile.yaml` |
| ปลุก MOB fallback — ให้ `internal_guard_payout_profile` คืนเบอร์จริงจาก identity (ต้องมี identity resolver ใน `ProfileInternalDeps`) | `services/profile/src/api/mod.rs:1509` |
| ช่อง "เลขบัตรประชาชน / เลขผู้เสียภาษี" ในหน้า guard detail ของ web-admin + ลิงก์จากตาราง "จ่ายไม่ได้" ในหน้า payouts ไปหน้าที่แก้ได้ | `apps/web-admin/app/(dashboard)/guards/*` · `payouts/page.tsx` |
| รปภ. คนเดียวที่ profile หาย ต้อง exclude แค่คนนั้น ไม่ใช่ทั้ง batch | `services/payment/src/api/payouts.rs:aggregate` |
| (ตามการตัดสินใจ) เก็บ tax_id ตอนสมัครใน mobile | `apps/mobile/lib/core/controllers/profile_controller.dart` |

**DoD:** admin กรอกเลขบัตร รปภ. 1 คน → คนนั้นโผล่ในหน้า preview → กด export ได้ไฟล์ที่มีชื่อคนนั้น

> ✅ **ทำแล้ว 5/6 แถว — DoD ผ่าน.** `validate_guard_tax_id` (mod-11 เฉพาะ 13 หลัก) + `COALESCE`
> ทั้ง 3 ทางเขียน · `PUT /admin/guard-profiles/{user_id}/payout` (merge semantics + `record_access`
> ก่อนเขียน = PDPA §30) · MOB fallback ปลุกแล้ว (เบอร์มาจาก **identity** ไม่ใช่โปรไฟล์) ·
> ช่องกรอก + ลิงก์จากตาราง "จ่ายไม่ได้" → `/guards?guard={id}` ·
> exclude ทีละคน (`ExcludedGuard` + เหตุผลไทย)
> ❌ **แถวสุดท้าย (เก็บ `tax_id` ตอนสมัครใน mobile) ยังไม่ทำ** — แอปไม่มีฟิลด์นี้เลย
> (`apps/mobile/lib` มีแต่ `tax_id` ของ**บริษัท**บนใบเสร็จ) วันนี้ admin เป็นคนกรอกให้ทางหน้า guard
> ยกเป็นหนี้ทางเทคนิค บันทึกไว้ใน `PROGRESS.md` แล้ว

### Phase 1 — ทำให้ไฟล์ผ่านสเปค SCB (pure domain ล้วน ไม่แตะ schema)

แก้ F1–F8 ทั้งหมดใน `services/payment/src/domain/scb_export.rs` + `api/payouts.rs`:
1. `WHTDET` เป็น record แยกบรรทัด (field 0 = `"WHTDET"`)
2. `batch_ref` = timestamp 12 หลักล้วน · `file_ref` = `batch_ref + product_code` · ชื่อไฟล์แยกจาก field
3. `value_date` คำนวณด้วย `Asia/Bangkok` + roll ไปวันทำการถัดไป + ให้ admin override ได้
4. normalize เป็นตัวเลขล้วนทุกฟิลด์ที่ธนาคาร parse เป็นตัวเลข
5. sanitize `|` + ตัดความยาวตาม cap (ชื่อ ≤140, ที่อยู่ ≤70, txn ref ≤20, system ref ≤18)
6. เช็คเพดานยอดต่อรายการ → **เกินให้ exclude พร้อมเหตุผลไทย ไม่ใช่เขียนบรรทัดเสีย**
7. เปลี่ยน default ภ.ง.ด. ตามการตัดสินใจ (แนะนำ `04` = ภ.ง.ด.3) + validate ค่าที่รับ

**DoD:** unit test ยืนยันทุกบรรทัด/ทุก field index ตรงกับ `CPX_Toolkit_Reverse_Engineering.md`
+ golden-file test เทียบไฟล์ทั้งไฟล์

> ✅ **ทำแล้ว F1–F8 ครบ** — แต่ **หัวข้อ "ไม่แตะ schema" ไม่จริง**: ข้อ 6 (เพดานยอด) ต้องปรับได้โดย
> ไม่ deploy จึงต้องมีคอลัมน์ `payout_config.max_transfer_per_txn` = **migration `0008`**
> นี่คือสาเหตุที่เลข migration ของทุก phase ถัดไปเลื่อนหมด (ดูตารางเลข migration ข้างบน)
> ข้อ 7 (default ภ.ง.ด.) **ยังเป็น `53`** — validate ค่าที่รับแล้ว (7 โค้ดตามเอกสาร) และ admin
> ตั้งเป็น `04` ได้ แต่ค่า default รอ §5 ข้อ 4 ที่ยัง open อยู่

### Phase 1.5 — แตก writer ให้รองรับหลาย product (เพิ่มใหม่ หลังผู้ใช้ยืนยันว่าข้อ 2 ออกไฟล์ด้วย)

`scb_export.rs` ตอนนี้ hardcode `PPY` ทั้งก้อน (`"111"`/`"0000"`) — stream 2 ต้องใช้ `OAT` จึงต้องแตกก่อน

| งาน | รายละเอียด |
|---|---|
| ทำ `product_code` ให้มีผลจริง end-to-end | คอลัมน์มีอยู่แล้วใน `payout_config` แต่ไม่เคยถูกอ่าน |
| branch `TXNDET` f3/f4/f5/f7 ตาม product (doc §7.2) | `PPY` → f3=proxy type · f4=`"111"` · f5=`"0000"` · `OAT` → f3 ว่าง · f4=รหัสธนาคาร 3 หลัก · f5=`"0111"` · f7=service type |
| validate เลขบัญชีปลายทางตาม product (doc §7.4) | `OAT` ต้องเป็นบัญชี SCB **10 หลักพอดี** + check-digit (§14 `CheckScbDigit`) · `PPY` 10–15 หลัก |
| ตาราง bank code + service type | เก็บเป็น lookup ที่ map ตรงตามรหัส ห้ามอิงลำดับ (doc เตือนว่ารหัสไม่เรียงกัน) |
| เพดานยอดต่อ product | `NAT`/`MOB` ฿2,000,000 · `EWL` ฿10,000 · `OAT` ไม่จำกัดแบบเดียวกัน |

**DoD:** unit test ยืนยันว่าไฟล์ `OAT` และไฟล์ `PPY` มี f3/f4/f5/f7 ต่างกันตามตาราง §7.2 เป๊ะ

> ✅ **ทำแล้ว** — `ScbProduct{PromptPay,OwnAccount}` + `CreditDestination{PromptPay,BankAccount}`:
> f3/f4 มาจาก**ปลายทางของผู้รับ** ส่วน f5/f7 มาจาก **product ของ batch** (กัน product/destination
> หลุดคู่กัน) · เพดานยอดอ่านจากปลายทาง (`EWL` ฿10,000 · `NAT`/`MOB` ฿2,000,000) · golden file **2 ใบ**

### Phase 2 — ปิดประตูทางเดียว (batch lifecycle · archive · void · audit)

| งาน | รายละเอียด | ทำจริง |
|---|---|---|
| ~~migration `payment/0008`~~ → **`0009_payout_batch_lifecycle.sql`** | `payout_batches`: `status` (~~`draft`~~ ตัดออก — ดูกล่องด้านล่าง) · ~~`file_key`~~ → **`file_text` อย่างเดียว** · `voided_at`/`voided_by`/`void_reason` (+`status_note`) · ~~snapshot config+PII~~ → **ตัว `file_text` คือ snapshot** · แก้ `recipient_count` (+backfill) | ✅ (เลขเปลี่ยนเพราะ P1 กิน `0008` ไป) |
| paid-marker รู้จัก lifecycle | backlog query ต้องข้าม item ที่อยู่ใน batch สถานะ `voided` → งานกลับเข้าคิวจ่ายรอบหน้า | ✅ ทำที่ **item** (`payout_batch_items.voided_at` + partial unique) ไม่ใช่ที่ batch — void รายคนได้ด้วย |
| ~~export 2 เฟส~~ | ~~generate → `draft`; ยืนยันตอน download สำเร็จ → `generated`~~ | ❌ **ไม่ทำโดยตั้งใจ** — ดูกล่องด้านล่าง |
| endpoints ใหม่ | `GET /admin/payouts/batches` · `GET …/{id}` · `GET …/{id}/file` (re-download) · `POST …/{id}/status` · `POST …/{id}/void` | ✅ ครบ **+ `POST …/{id}/items/void`** ที่แผนไม่ได้เขียนไว้ (ดึงงานรายคนกลับเข้าคิว) — ชิปทั้ง 3 stream (`payouts`/`refunds`/`deductions`) |
| audit log | append-only ทุก action ที่ขยับเงิน (ใคร/เมื่อไหร่/จำนวน) | ✅ `payment.money_audit` — **4 action ต่อ stream** (`*_exported` · `*_status_changed` · `*_voided` · `*_items_voided`) |
| web-admin | แท็บ "ประวัติไฟล์โอน" — สถานะ, ดาวน์โหลดซ้ำ, มาร์ก uploaded/confirmed/rejected, void พร้อมเหตุผล | ✅ `payouts/page.tsx` + `batch-detail-modal.tsx` |
| แจ้งเตือน | รปภ. ได้รับแจ้งเมื่อเงินโอนแล้ว | ❌ **ยังไม่ทำ** — ไม่มีโค้ดส่ง notification (มีแต่ `sms_notify` ของ SCB ซึ่งปิดไว้ default) → P2 ยังเป็น `[~]` ใน `PROGRESS.md` |

**DoD:** void batch → งานกลับเข้า preview รอบถัดไป · double-pay ยังเป็นไปไม่ได้ · มี audit row ทุก action

> 🔻 **ตัดสินใจ: ไม่ทำ two-phase draft (ตัด `draft` ออกจาก vocabulary)**
> `status` ที่ชิปจริงมี **5 ค่า** — `generated` · `uploaded` · `confirmed` · `rejected` · `voided`
> (CHECK ใน `0009` + ตารางทรานสิชันบริสุทธิ์ที่ `services/payment/src/domain/batch_status.rs`)
>
> **เหตุผล:** บั๊กที่ต้องปิดคือ *"โหลดไฟล์ไม่สำเร็จแล้วงานถูกมาร์กว่าจ่ายแล้วถาวร"* —
> **เก็บ `file_text` ไว้ + มี `void`** ปิดบั๊กนั้นครบ (โหลดซ้ำได้เสมอ · ถ้าธนาคารตีกลับก็ void แล้วงาน
> กลับเข้าคิว) โดยไม่สร้าง failure mode ใหม่ ส่วน `draft` **แลกบั๊กเป็นบั๊ก**: ถ้า client ตายหลังโหลด
> แต่ก่อน confirm งานจะค้างในสถานะที่ **"จ่ายก็ไม่ได้ คืนคิวก็ไม่ได้"** ซึ่งแย่กว่าเดิมเพราะไม่มี action
> ไหนพาออกจากสถานะนั้นได้เลย เหตุผลเต็มอยู่ที่หัวไฟล์ `0009` และใน `PROGRESS.md`

### Phase 3 — Stream 1: ไฟล์โอนคืนลูกค้า

| งาน | รายละเอียด |
|---|---|
| **ปลายทางรับเงิน** (ขึ้นกับการตัดสินใจข้อ 1) | ทางเลือก A: PromptPay ด้วย `contact_phone` ที่มีอยู่แล้ว (ถูกที่สุด, reuse `generate()` ได้เลย) · ทางเลือก B: เพิ่มคอลัมน์ bank ใน `customer_profiles` + flow เก็บข้อมูล + product `3PT/RFT` (ต้องแตก writer) |
| `GET /internal/customers/{id}/payout-profile` บน profile + เพิ่ม method ใน `ProfileReader` ของ payment | mirror ของฝั่ง รปภ. |
| ~~migration `payment/0009`~~ → **`0011_refund_batches.sql`** | `refund_batches` + `refund_batch_items` พร้อม **UNIQUE paid-marker ที่ครอบทั้ง 2 lane** (`payments` และ `payment_slips`) — ชิปเป็น composite `(source_kind, source_id)` + lifecycle ครบตั้งแต่วันแรก (เรียนจาก stream ③) |
| repo | backlog = **UNION** ของ 2 lane · batch writer ที่ **ขยับ `refund_status` → `'processed'`** ในทรานแซกชันเดียวกัน |
| API | `GET /admin/refunds/preview` · `POST /admin/refunds/export` (ใช้ `scb_export::generate` เดิม, `wht = 0` → ไม่มี `WHTCER` เพราะเงินคืนไม่ใช่เงินได้พึงประเมิน) · `POST /admin/refunds/{source}/{id}/process` (มาร์กมือ) |
| gateway + env | `/admin/refunds` มี rule อยู่แล้ว ✅ · เพิ่ม `IDENTITY_URL` ให้ payment ถ้าเลือกทางเลือก A |
| web-admin | หน้า `/refunds` จริง — tick-list + ช่วงวันที่ + export + ประวัติ (แทนโน้ต "รอ API") |

**DoD:** export 2 รอบติดกันไม่คืนเงินคนเดิมซ้ำ · คิว `pending` ระบายได้จริง · ครอบคลุมทั้ง 2 lane

> ✅ **ทำแล้วทั้ง phase — เลือกทางเลือก A.** จุดที่ต่างจากแผน: **payment ไม่ได้รับ `IDENTITY_URL`**
> เพราะ profile เป็นคนคุยกับ identity ให้แล้วใน `/internal/customers/{user_id}/payout-profile`
> (`contact_phone` → fallback เบอร์ login) — payment ยังถือแค่ `PROFILE_URL` ตามกติกา per-service ·
> lifecycle/void/`items/void` ยกมาจาก P2 ทั้งชุด · หน้า `/refunds` เป็น route ใหม่แยกจาก `/wallet`
> และลบโน้ต "รอ API" ในหน้า wallet ที่ตอนนี้ผิดแล้ว · ไฟล์ยังเขียนด้วย `scb_export::generate` ตัวเดิม
> (`domain/refund_export.rs` มีแค่ตรรกะ**เลือก**รายการ + ระบุตัวตนหนี้ 2 lane — ไม่มี writer ตัวที่สอง)
> ❌ **`POST /admin/refunds/{source}/{id}/process` (มาร์กมือ) ไม่ได้ทำ** — เส้นทางเดียวที่ปิดคิวได้คือ
> export (แล้ว void ถ้าธนาคารตีกลับ) ซึ่งทำให้ทุกการปิดคิวมีไฟล์ + `money_audit` รองรับเสมอ
> ถ้าจะเพิ่มทีหลังต้องคิดเรื่อง audit ของ "คืนเงินนอกไฟล์" ให้จบก่อน

### Phase 4 — Stream 2: ไฟล์ `OAT` sweep ยอดหักเข้าระบบ + รายงานภาษี

| งาน | รายละเอียด |
|---|---|
| ~~migration `payment/0010`~~ → **`0013_platform_cut_sweep.sql`** (+ **`0014`** จากรอบ review) | snapshot `base_fee` / `booked_hours` / `guard_count` / `tip` / **`commission_amount` (บาท)** ลงบน `payment.payments` ตอน settle → ยอดหักคำนวณได้ใน SQL ล้วน ไม่ต้อง fan-out · `0013` เพิ่ม `deduction_batches`/`_items` ด้วย · `0014` เพิ่ม `uncollected` |
| pure domain | `settlement::split()` + invariant `customer_paid = guard_transfer + commission + vat + wht + cancel_fee + refund` — **ชิปจริงมี `uncollected` เพิ่ม** (`0014`): `platform_cut = commission + cancel_fee + tip + unpaid_guard_share + rounding − uncollected` |
| ~~`GET /admin/reports/platform-cut`~~ → **`GET /admin/deductions/preview`** | แยกรายการ: `commission` · `cancellation_fee` · `tip` · `unpaid_guard_share` · **`vat_not_swept`** (ชื่อฟิลด์บอกเองว่าเป็นหนี้สรรพากร ไม่ใช่กำไร และไม่ได้อยู่ในไฟล์) ครบทั้งรายงานต่อ job และยอดรวม — **ไม่ได้ทำเป็น endpoint แยกใต้ `/admin/reports`**: ตัวเลขชุดเดียวกันนี้คือ preview ของไฟล์ sweep อยู่แล้ว การมี 2 endpoint ที่คิดยอดหักคนละที่คือบั๊กเงินรอเกิด (preview กับ export ใช้ `aggregate()` ตัวเดียวกันด้วยเหตุผลเดียวกัน) |
| `GET /admin/reports/vat-register` | รายงานภาษีขาย ภ.พ.30 รายเดือน (bucket ที่ `paid_at`) ✅ |
| `GET /admin/reports/wht-payees` | รายชื่อผู้ถูกหัก ภ.ง.ด.3/53 (TIN · ชื่อ · ที่อยู่ · ประเภทเงินได้ · ยอดจ่าย · ภาษีหัก) จาก `payout_batch_items` (bucket ที่ `value_date`) ✅ |
| **ไฟล์ SCB `OAT`** | `GET /admin/deductions/preview` + `POST /admin/deductions/export` — sweep ยอดหักตามช่วงวันที่ เข้าบัญชีรายได้บริษัท (บัญชีปลายทางเป็น config ใหม่) พร้อม **paid-marker กัน sweep ซ้ำ** แบบเดียวกับ payout ✅ (1 batch = **1 `TXNDET`** เพราะปลายทางคือบัญชีบริษัทบัญชีเดียว) |
| CSV download + หน้า web-admin "ยอดหักเข้าระบบ" | ✅ **CSV มีที่ 2 รายงานภาษี** (`?format=csv` เรนเดอร์ฝั่ง server: RFC 4180 + BOM + กัน formula injection) · หน้า `/deductions` = preview + ปุ่มออกไฟล์ + ประวัติ + 2 รายงาน — **preview ยอดหักยังไม่มีปุ่ม CSV** |

**DoD:** ตัวเลข tie-out กับ `payout_batches.total_amount` และ `refund_batches` ได้

> ✅ **ทำแล้วทั้ง phase.** สรุปให้ตรงตัวเลข: **รายงานภาษี 2 ใบ** (`vat-register` · `wht-payees`,
> CSV ทั้งคู่) ไม่ใช่ 3 — ส่วน "ยอดหักแยกรายการ" ไปอยู่ใน `/admin/deductions/preview` ตามเหตุผลข้างบน
> · ไม่ต้องเพิ่ม migration ให้ `scb_file_refs` เพราะ `0012` เปิด `stream = 'deduction'` รอไว้แล้ว

### Phase 5 (ถ้าจำเป็น) — reconciliation + import ผลลัพธ์จากธนาคาร

> ⏳ **ยังไม่ทำ** (ยังไม่รู้ว่า SCB ให้ result file แบบไหน) — ยังเป็น `[ ]` ใน `PROGRESS.md`

- `GET /admin/reports/reconciliation` — ทวนสามส่วนเทียบ statement
- import result file จาก SCB (ถ้ามี) → auto un-mark รายการที่ธนาคารตีกลับ
- alert รายการ `pending` ที่ค้างเกิน N วัน

---

## 5. เรื่องที่ต้องตัดสินใจก่อน (blocking)

> ทวนทุกแถวกับโค้ดจริงเมื่อ **2026-09-07** — คอลัมน์ขวาสุดคือ "ชิปแล้วหรือยัง" ไม่ใช่แค่ "ตอบแล้วหรือยัง"

| # | คำถาม | ทำไมสำคัญ | คำแนะนำ / คำตอบ | ชิปแล้ว? |
|---|---|---|---|---|
| 1 | ~~คืนเงินลูกค้าทางไหน~~ | — | ✅ **ตอบแล้ว: ใช้ข้อมูลตอนลงทะเบียน** (เบอร์ที่สมัคร → พร้อมเพย์ `MOB`) | ✅ P3 — `/internal/customers/{user_id}/payout-profile` (`contact_phone` → fallback เบอร์ login) ไม่เก็บ PII ใหม่ ไม่ต้อง migration |
| 2 | **ทิปควรถึง รปภ. ไหม** | ถ้าใช่ = บั๊กเงิน ต้องแก้ + กระทบ payout ย้อนหลังทั้งหมด | ⏸️ **เลื่อนไว้ก่อน** (ผู้ใช้เลือก) | ⏸️ **ยัง open** — วันนี้ทิปถูกนับเป็น `JobSettlement::tip` = ส่วนหนึ่งของ platform cut และ **sweep เข้าบัญชีบริษัทจริงแล้ว** ถ้าเปลี่ยนใจต้องแก้ทั้ง payout และ sweep |
| 3 | **`guard_count` > 1 ขายจริงไหม** | ถ้าขาย ต้องมี assignments model ก่อนคำนวณยอดหักได้ | ⏸️ **เลื่อนไว้ก่อน** (ผู้ใช้เลือก) — แต่ยอดหักของ Phase 4 จะรวมค่าแรงที่ไม่ได้จ่ายไว้ด้วย ต้องรู้ตัว | ⏸️ **ยัง open** — ชิปเป็น `JobSettlement::unpaid_guard_share` แยกบรรทัดใน preview (ไม่ซ่อนใน commission) แล้ว sweep ไปด้วย ตามที่เตือนไว้ |
| 4 | **ภ.ง.ด.3 หรือ 53** | ฟอร์มผิด = ยื่นผิด; proxy เป็นเลขบัตร ปชช. = บุคคลธรรมดา | **ภ.ง.ด.3 (`04`)** ถ้า รปภ. เป็นบุคคลธรรมดา | ⏳ **ยัง open** — default ยังเป็น `'53'` (mig `0007`) ที่ชิปคือ **validate** ค่าที่รับ (7 โค้ดตามเอกสาร ทั้งตอนตั้ง config และตอน export) + admin ตั้ง `04` เองได้ · เปลี่ยน default = migration ใหม่ |
| 5 | ~~stream 2 เป็นรายงานไหม~~ | — | ✅ **ตอบแล้ว: ออกไฟล์ SCB `OAT` ด้วย** → เพิ่ม Phase 1.5 + แก้ Phase 4 | ✅ P1.5 + P4 — `OAT` เป็น product จริง end-to-end + `/admin/deductions/export` |
| 6 | ~~เพดานยอด PromptPay~~ | — | ✅ **คลี่จากเอกสารแล้ว: ฿2,000,000** (`NAT`/`MOB`) · ฿10,000 เป็นของ `EWL` | ✅ P1 — mig `0008` `max_transfer_per_txn` (default 2,000,000, ปรับได้ไม่ต้อง deploy) + เพดานต่อปลายทางใน `scb_max_transfer` · เกินเพดาน = **exclude พร้อมเหตุผลไทย** ไม่ใช่บรรทัดเสีย |
| 7 | ~~ใครแบกค่าธรรมเนียมโอน (OUR/BEN)~~ | BEN = รปภ. ได้เงินน้อยกว่าที่ ledger บันทึก | ✅ **ตอบแล้ว: `OUR`** | ✅ P2 (review) — mig `0010` `fee_charge_code TEXT NOT NULL DEFAULT 'OUR'` + `CHECK IN ('BEN','OUR')` · `OUR` เป็นค่าเดียวที่ทำให้ รปภ. ได้รับ **เท่ากับ `payout_batch_items.transfer_amount` เป๊ะ** ledger กับ statement จึงตรงกัน (`BEN` = ธนาคารหักค่าฟีจากยอดโอน → ต่างกันถาวรโดยไม่มีร่องรอยฝั่งเรา) · ก่อนหน้านี้ `TXNDET` f8 ออกไปเป็นค่าว่างทั้งที่ `ValidCreditMandatory` บังคับ (doc:1721, 1915) |

---

## 6. อ้างอิง
- SCB format: `docs/reviews/CPX_Toolkit_Reverse_Engineering.md` (เลขบรรทัด `doc:NNNN` ในเอกสารนี้อ้างไฟล์นี้)
- **Stream ③ guard payout:** `services/payment/src/{domain/scb_export.rs,domain/payout.rs,domain/batch_status.rs,api/payouts.rs}` ·
  mig `payment/0007`–`0010` · `apps/web-admin/app/(dashboard)/payouts/`
- **Stream ① customer refund:** `services/payment/src/{domain/refund_export.rs,api/refunds.rs}` ·
  mig `payment/0011`, `0012` · `apps/web-admin/app/(dashboard)/refunds/` ·
  `services/profile/src/api/mod.rs` (`internal_customer_payout_profile`)
- **Stream ② platform cut:** `services/payment/src/{domain/settlement.rs,domain/deduction.rs,api/deductions.rs,api/reports.rs}` ·
  mig `payment/0013`, `0014` · `apps/web-admin/app/(dashboard)/deductions/`
- **เหตุผลของแต่ละการตัดสินใจ อยู่ที่หัวไฟล์ migration** — เขียนไว้ว่า "แก้บั๊กอะไร และทำไมถึงเลือกทางนี้"
  (`0009` = ทำไมไม่ทำ two-phase draft · `0010` = ทำไม `OUR` · `0012`/`0014` = สองรอบ review ที่แผนไม่ได้คาด)
- **ผลสำรวจเต็ม (89 confirmed gaps) = §1–§3 ของเอกสารนี้เอง** ทุกข้อมี path + เลขบรรทัดกำกับให้ไล่ย้อนได้
  ส่วนสถานะรายงานว่าอะไรทำแล้ว/ยังไม่ทำ ดู `PROGRESS.md` หัวข้อ 🏦 Bank export
