import type { components } from "@/api/generated/payment";
import type { Lang } from "@/lib/lang";

/**
 * The five lifecycle states a generated payout file can be in, taken FROM the contract rather than
 * re-typed here (`services/payment/src/domain/batch_status.rs` › `BatchStatus`). Used as the key of
 * the `statusLabels` record below, so the day a sixth state is added to the OpenAPI enum the build
 * breaks until BOTH locales name it — a status the admin sees as a raw `"partially_settled"` is
 * worse than no status at all on a money screen.
 */
export type BatchStatusValue = components["schemas"]["PayoutBatch"]["status"];

/**
 * The steps `POST /admin/payouts/batches/{id}/status` accepts — deliberately derived from the
 * REQUEST schema, not from `BatchStatusValue`. `generated` (only ever the initial state) and
 * `voided` (its own endpoint, because it must also un-mark every item and carry a reason) are not
 * in this union, so the UI cannot offer a button the endpoint would answer with a 400.
 */
export type BatchStep = components["schemas"]["SetPayoutBatchStatusRequest"]["status"];

/**
 * The ONLY ภ.ง.ด. form codes SCB Business Net accepts, from the CPX toolkit's `TBWHTType` lookup
 * (`docs/reviews/CPX_Toolkit_Reverse_Engineering.md:142-155`) — the dropdown that feeds the WHT
 * sheet's column O and resolves into the `WHT Form Type Code` helper column P.
 *
 * Deliberately NON-CONTIGUOUS (01, 03, 04, 11, 12, 13, 53 — the doc calls this out at :155): a
 * free-text box let an operator type "3" or "53 " and produce a file the bank rejects, which is
 * why this is a closed list. The stored default stays "53" — which form is owed is a TAX decision,
 * not a UI one; this only makes the choice visible and deliberate.
 */
export const WHT_FORM_CODES = ["01", "03", "04", "11", "12", "13", "53"] as const;
export type WhtFormCode = (typeof WHT_FORM_CODES)[number];

/**
 * Who bears the transfer fee — `TXNDET` field 8, taken FROM the contract so the two values can
 * never drift apart from the enum payment validates against (`Master_data!TBFeeOther`).
 *
 * The field is mandatory on every credit line, which is why it is a two-option picker and not an
 * optional one: a blank field 8 is a file SCB refuses.
 */
export type FeeChargeCode = NonNullable<components["schemas"]["PayoutConfig"]["fee_charge_code"]>;
export const FEE_CHARGE_CODES: readonly FeeChargeCode[] = ["OUR", "BEN"];

/**
 * Server-side cap on a note/reason (`MAX_NOTE_CHARS` in `services/payment/src/api/payouts.rs`,
 * counted with `chars().count()`). Mirrored on every textarea that feeds one so a long note is
 * stopped at the keyboard instead of coming back as a 400 with the typed text lost.
 *
 * `maxLength` counts UTF-16 units where the server counts code points, so the browser is the
 * STRICTER of the two for anything above the BMP (an emoji: 2 here, 1 there) and identical for
 * Thai. Erring that way is the safe direction — the UI can never let through a note the server
 * would refuse.
 */
export const MAX_NOTE_CHARS = 500;

/**
 * How many bookings ONE per-guard release may name (`MAX_VOIDED_ITEMS`,
 * `services/payment/src/domain/payout.rs`). Mirrored so a large tick-list is caught with a
 * "split it into several passes" message BEFORE the round-trip — the endpoint is all-or-nothing,
 * so an over-cap call releases nothing and the admin would be left guessing which half failed.
 */
export const MAX_RELEASE_ITEMS = 500;

/** Page copy for the guard-payout (SCB export) screen — Thai default, English parity. */
export const COPY: Record<
  Lang,
  {
    title: string;
    subtitle: string;
    settings: string;
    debitAccount: string;
    feeDebitAccount: string;
    /** The company account the PLATFORM-CUT sweep (stream ②, product `OAT`) is credited to. It is
     *  set here, with the other company bank details, but it is spent on the `/deductions` screen —
     *  so the label has to say which file it belongs to or it reads as a fourth payout account. */
    revenueAccount: string;
    /** Why a typo here is worse than elsewhere: an `OAT` line may credit no other bank, and the
     *  check digit is validated at save AND again at export — after the jobs are marked swept. */
    revenueAccountHint: string;
    whtRate: string;
    whtForm: string;
    /** `Record<WhtFormCode, …>` so adding a code forces a label in BOTH locales. */
    whtFormLabels: Record<WhtFormCode, string>;
    /** Which form goes with which kind of recipient — the one thing an operator gets wrong. */
    whtFormHint: string;
    /** Shown for a stored code that is NOT in `WHT_FORM_CODES` (legacy/hand-edited row): kept
     *  selectable so we never silently rewrite the operator's tax setting, but flagged. */
    whtFormUnknown: (code: string) => string;
    whtFormUnset: string;
    incomeType: string;
    incomeDesc: string;
    /** Who pays the bank's transfer fee (`TXNDET` field 8). Mandatory on every credit line. */
    feeCharge: string;
    /** `Record<FeeChargeCode, …>` so a third code in the contract forces a label in BOTH locales. */
    feeChargeLabels: Record<FeeChargeCode, string>;
    /** The consequence, not the definition: `BEN` makes the guard receive LESS than we recorded. */
    feeChargeHint: string;
    /** Ask SCB to SMS each guard about their transfer (`TXNDET` fields 9/10). */
    smsNotify: string;
    /** What it costs and what it discloses — the bank bills per message and gets the guard's phone. */
    smsNotifyHint: string;
    /** The toggle's own state, read out next to it (a bare switch says nothing on its own). */
    smsNotifyOn: string;
    smsNotifyOff: string;
    /** Per-transaction transfer ceiling — a guard over it is EXCLUDED from the file, not truncated. */
    maxTransfer: string;
    maxTransferHint: string;
    save: string;
    saved: string;
    preview: string;
    refresh: string;
    dateFrom: string;
    dateTo: string;
    applyFilter: string;
    clearFilter: string;
    selectAll: string;
    selectOne: string;
    pickSomeone: string;
    selectedOnly: string;
    ofTotal: (total: number) => string;
    guard: string;
    proxy: string;
    income: string;
    wht: string;
    transfer: string;
    totalTransfer: string;
    totalWht: string;
    recipients: string;
    excludedTitle: string;
    /** Tells the admin the id is a link to the place the missing data is entered. */
    excludedHint: string;
    /** Accessible name of that per-row link (the visible text is just the short id). */
    fixGuard: string;
    reason: string;
    jobs: string;
    nobody: string;
    exportBtn: string;
    exporting: string;
    exportHint: string;
    loadError: string;
    saveError: string;
    exportError: string;
    nothingToPay: string;

    // ── Batch history: what happened to the files we already generated ──────────────────
    history: string;
    /** Why the list exists at all — the export is a one-way door and this is the way back. */
    historyHint: string;
    historyEmpty: string;
    historyError: string;
    fileRef: string;
    valueDate: string;
    people: string;
    totalAmount: string;
    status: string;
    createdAt: string;
    actions: string;
    /** Lifecycle state names. Thai mirrors `BatchStatus::label_th()` word for word so the badge
     *  and the server's own 409 message ("ไฟล์นี้อยู่ในสถานะ …") never disagree. */
    statusLabels: Record<BatchStatusValue, string>;
    /** Button labels — the step being RECORDED ("mark uploaded"), not the state's name. */
    stepLabels: Record<BatchStep, string>;
    redownload: string;
    /** Tooltip on the disabled re-download of a pre-Phase-2 batch (its text was never stored). */
    noStoredFile: string;
    downloadError: string;
    recordTitle: (step: string) => string;
    /**
     * Body for the REVERSIBLE steps only (`uploaded`, `rejected`). Its reassurance ("nothing is
     * sent to SCB, no amount changes") is true for those two and dangerously false for
     * `confirmed`, which is why that step has its own [confirmedWarning] instead of sharing this.
     */
    recordBody: (step: string) => string;
    /**
     * Body for the `confirmed` step — the one-way door. Confirming makes the batch TERMINAL: the
     * whole-file void disappears from the row and every job in it stays จ่ายแล้ว. Says so plainly,
     * and names the recourse that DOES survive (the per-job release) so the warning is honest
     * about what is left rather than overstating the finality.
     */
    confirmedWarning: string;
    noteLabel: string;
    noteHint: string;
    voidBtn: string;
    voidTitle: string;
    /** The consequence, in plain words — this is the sentence that has to stop a mis-click. */
    voidWarning: (recipients: number, amount: string) => string;
    voidReason: string;
    voidReasonHint: string;
    voidReasonPlaceholder: string;
    voidConfirm: string;
    /** The void modal's DISMISS button. Its own key because Thai "ยกเลิก" means both "dismiss this
     *  dialog" and "void the file" — sitting next to "ยืนยันยกเลิกไฟล์" that is the one ambiguity
     *  on this screen we cannot afford. Reads as the plain opposite of the confirm instead. */
    keepFile: string;
    /** Prefixes the stored reason where it is shown back in the history row. */
    voidedReasonPrefix: string;
    cancel: string;
    actionError: string;
    listSummary: (from: number, to: number, total: number) => string;

    // ── Batch detail + per-guard release (batch-detail-modal.tsx) ───────────────────────
    /** The jobs ONE file paid, and the way to hand a bounced transfer back to the queue. */
    detail: {
      /** History-row button that opens the drill-down. */
      viewItems: string;
      title: string;
      /** The file ref, spelled out under the title so the modal is anchored to a real file. */
      subtitle: (fileRef: string) => string;
      loading: string;
      error: string;
      empty: string;
      colGuard: string;
      colJobs: string;
      colIncome: string;
      colWht: string;
      colTransfer: string;
      colState: string;
      /** Per-row state of the paid-marker: still paid, or already handed back to the queue. */
      statePaid: string;
      stateReleased: string;
      /** Why this screen exists — the bank took the FILE but bounced ONE credit line. */
      releaseIntro: string;
      selectGuard: string;
      selectAll: string;
      /** Running total of what is ticked, so the release is confirmed against a number. */
      selectedSummary: (guards: number, jobs: number, amount: string) => string;
      nothingSelected: string;
      /** The consequence line above the reason box — the sentence that must stop a mis-click. */
      releaseWarning: string;
      releaseReason: string;
      releaseReasonHint: string;
      releaseReasonPlaceholder: string;
      releaseBtn: string;
      releasing: string;
      releasedFlash: (guards: number) => string;
      releaseError: string;
      /** The endpoint's own per-call cap (`MAX_VOIDED_ITEMS`), hit before the round-trip. */
      tooMany: (max: number) => string;
      close: string;
    };
  }
> = {
  th: {
    title: "จ่ายเงิน รปภ (ไฟล์อัปโหลด SCB)",
    subtitle:
      "รวมยอดค้างจ่ายของ รปภ ที่งานเสร็จแล้ว → สร้างไฟล์อัปโหลด SCB Business Net (พร้อมเพย์ + หัก ณ ที่จ่าย ภงด.53)",
    settings: "ตั้งค่าการจ่าย",
    debitAccount: "บัญชีตัดเงินบริษัท",
    feeDebitAccount: "บัญชีหักค่าธรรมเนียม (เว้นว่าง = ใช้บัญชีตัดเงิน)",
    revenueAccount: "บัญชีรับรายได้บริษัท (ปลายทางไฟล์กวาดยอดหักเข้าระบบ)",
    revenueAccountHint:
      "ใช้เฉพาะกับไฟล์ “ยอดหักเข้าระบบ” (OAT) เท่านั้น ไม่เกี่ยวกับไฟล์จ่าย รปภ หรือไฟล์คืนเงิน — ต้องเป็นบัญชี SCB 10 หลักที่เลขตรวจสอบถูกต้อง ระบบตรวจทั้งตอนบันทึกและตอนสร้างไฟล์ ถ้ายังไม่ตั้ง จะสร้างไฟล์กวาดยอดไม่ได้",
    whtRate: "อัตราหัก ณ ที่จ่าย (%)",
    whtForm: "แบบ (ภ.ง.ด.)",
    whtFormLabels: {
      "01": "01 — ภ.ง.ด.1ก",
      "03": "03 — ภ.ง.ด.2",
      "04": "04 — ภ.ง.ด.3",
      "11": "11 — ภ.ง.ด.1ก พิเศษ",
      "12": "12 — ภ.ง.ด.2ก",
      "13": "13 — ภ.ง.ด.3ก",
      "53": "53 — ภ.ง.ด.53",
    },
    whtFormHint: "ภ.ง.ด.3 สำหรับบุคคลธรรมดา · ภ.ง.ด.53 สำหรับนิติบุคคล",
    whtFormUnknown: (code) => `${code} — รหัสนี้ SCB ไม่รับ (เลือกใหม่)`,
    whtFormUnset: "— ยังไม่ได้เลือก —",
    incomeType: "ประเภทเงินได้",
    incomeDesc: "คำอธิบายเงินได้",
    feeCharge: "ผู้รับผิดชอบค่าธรรมเนียมโอน",
    feeChargeLabels: {
      OUR: "OUR — บริษัทออกค่าธรรมเนียมเอง (แนะนำ)",
      BEN: "BEN — หักค่าธรรมเนียมจากเงินที่โอนให้ รปภ",
    },
    feeChargeHint:
      "เลือก BEN = ธนาคารหักค่าธรรมเนียมออกจากยอดโอน รปภ จะได้รับเงินน้อยกว่ายอด “โอนจริง” ที่ระบบบันทึกไว้ว่าจ่ายแล้ว บัญชีของเรากับของธนาคารจะไม่ตรงกันถาวร — ปกติให้ใช้ OUR",
    smsNotify: "ให้ธนาคารส่ง SMS แจ้ง รปภ",
    smsNotifyHint:
      "เปิด = ส่งเบอร์โทรของ รปภ ไปกับไฟล์เพื่อให้ SCB ส่ง SMS แจ้งเงินเข้า ธนาคารคิดค่าบริการเป็นรายข้อความ · ปิด = ไม่ส่งเบอร์ไปกับไฟล์เลย (ไม่กระทบการโอน — พร้อมเพย์ปลายทางยังใช้เลขเดิม)",
    smsNotifyOn: "เปิด — ส่งเบอร์ รปภ ไปกับไฟล์",
    smsNotifyOff: "ปิด — ไม่ส่งเบอร์ไปกับไฟล์",
    maxTransfer: "เพดานยอดโอนต่อรายการ (บาท)",
    maxTransferHint:
      "รปภ ที่ยอดโอนรวมเกินเพดานนี้จะถูกกันออกจากไฟล์ (ขึ้นในตาราง “จ่ายไม่ได้”) ไม่ได้ถูกตัดยอด — งานยังค้างรอจ่ายอยู่ ค่ามาตรฐาน 2,000,000 (วงเงินพร้อมเพย์/ORFT ต่อรายการ) · เว้นว่าง = คงค่าเดิม (ล้างค่าจากหน้านี้ไม่ได้)",
    save: "บันทึกการตั้งค่า",
    saved: "บันทึกแล้ว",
    preview: "พรีวิวรายการจ่าย",
    refresh: "รีเฟรช",
    dateFrom: "งานที่เสร็จตั้งแต่",
    dateTo: "ถึงวันที่",
    applyFilter: "ใช้ตัวกรอง",
    clearFilter: "ล้างตัวกรอง",
    selectAll: "เลือกทั้งหมด",
    selectOne: "เลือก",
    pickSomeone: "ยังไม่ได้เลือก รปภ — ติ๊กอย่างน้อย 1 คนเพื่อสร้างไฟล์",
    selectedOnly: "เฉพาะที่เลือก",
    ofTotal: (total) => `จากทั้งหมด ${total} คน`,
    guard: "รปภ",
    proxy: "พร้อมเพย์",
    income: "เงินได้",
    wht: "หัก ณ ที่จ่าย",
    transfer: "โอนจริง",
    totalTransfer: "ยอดโอนรวม",
    totalWht: "หัก ณ ที่จ่ายรวม",
    recipients: "จำนวนผู้รับ",
    excludedTitle: "จ่ายไม่ได้ (ต้องแก้ข้อมูลก่อน)",
    excludedHint:
      "กดที่รหัส รปภ เพื่อไปกรอกเลขบัตรประชาชน/บัญชีธนาคารให้ครบ แล้วกลับมากดรีเฟรช — งานของคนกลุ่มนี้ยังค้างอยู่ ไม่ได้หายไป",
    fixGuard: "ไปแก้ข้อมูลจ่ายเงินของ รปภ",
    reason: "เหตุผล",
    jobs: "งาน",
    nobody: "ไม่มีรายการค้างจ่ายในขณะนี้",
    exportBtn: "สร้างไฟล์อัปโหลด SCB",
    exporting: "กำลังสร้างไฟล์…",
    exportHint:
      "ไฟล์เดียวจ่ายได้หลายคน — 1 รปภ = 1 รายการโอน (รวมทุกงานของคนนั้น). กดแล้วจะดาวน์โหลดไฟล์ .txt และบันทึกเฉพาะคนที่เลือกว่าจ่ายแล้ว (กันจ่ายซ้ำ) คนที่ไม่ได้เลือกจะยังค้างอยู่ในรอบถัดไป",
    loadError: "โหลดข้อมูลไม่สำเร็จ",
    saveError: "บันทึกไม่สำเร็จ",
    exportError: "สร้างไฟล์ไม่สำเร็จ",
    nothingToPay: "ไม่มีรายการที่จ่ายได้ในขณะนี้",

    history: "ประวัติไฟล์โอน",
    historyHint:
      "ไฟล์ที่สร้างไปแล้วทั้งหมด (ใหม่สุดอยู่บน) — ดาวน์โหลดซ้ำได้ถ้าไฟล์เดิมหาย และบันทึกได้ว่าธนาคารรับหรือปฏิเสธ",
    historyEmpty: "ยังไม่เคยสร้างไฟล์โอน",
    historyError: "โหลดประวัติไฟล์ไม่สำเร็จ",
    fileRef: "รหัสไฟล์ (SCB)",
    valueDate: "วันที่เงินเข้า",
    people: "จำนวนคน",
    totalAmount: "ยอดรวม",
    status: "สถานะ",
    createdAt: "วันที่สร้าง",
    actions: "จัดการ",
    statusLabels: {
      generated: "สร้างไฟล์แล้ว",
      uploaded: "อัปโหลดเข้าธนาคารแล้ว",
      confirmed: "ธนาคารยืนยันแล้ว",
      rejected: "ธนาคารปฏิเสธ",
      voided: "ยกเลิกแล้ว",
    },
    stepLabels: {
      uploaded: "อัปโหลดแล้ว",
      confirmed: "ธนาคารยืนยัน",
      rejected: "ธนาคารปฏิเสธ",
    },
    redownload: "ดาวน์โหลดซ้ำ",
    noStoredFile: "ไฟล์นี้สร้างก่อนระบบจะเก็บสำเนา จึงดาวน์โหลดซ้ำไม่ได้",
    downloadError: "ดาวน์โหลดไฟล์ไม่สำเร็จ",
    recordTitle: (step) => `บันทึกสถานะ: ${step}`,
    recordBody: (step) =>
      `บันทึกว่าไฟล์นี้ “${step}” — เป็นการบันทึกสิ่งที่เกิดขึ้นจริงที่ธนาคาร ไม่ได้ส่งอะไรไปที่ SCB และไม่กระทบยอดเงิน`,
    confirmedWarning:
      "ขั้นนี้ย้อนกลับไม่ได้ กดเมื่อเห็นเงินออกจากบัญชีบริษัทจริงแล้วเท่านั้น — หลังกดจะ “ยกเลิกทั้งไฟล์” ไม่ได้อีก และงานทุกงานในไฟล์นี้จะถูกนับว่าจ่ายแล้วถาวร ถ้ากดผิดไฟล์หรือกดก่อนเงินออกจริง งานกลุ่มนั้นจะไม่กลับเข้าคิวรอจ่ายเอง · ทางออกที่ยังเหลืออยู่: ถ้าธนาคารโอนไม่สำเร็จบางราย ให้เปิด “ดูงานในไฟล์” แล้วดึงกลับเป็นรายคน",
    noteLabel: "หมายเหตุ (ไม่บังคับ)",
    noteHint: "เช่น ข้อความที่ธนาคารตอบกลับมา — ไม่เกิน 500 ตัวอักษร",
    voidBtn: "ยกเลิกไฟล์",
    voidTitle: "ยกเลิกไฟล์โอนนี้?",
    voidWarning: (recipients, amount) =>
      `งานทั้งหมดในไฟล์นี้ (รปภ ${recipients} คน · ฿${amount}) จะกลับเข้าคิว “รอจ่าย” และจ่ายใหม่ได้ในไฟล์รอบถัดไป — ยกเลิกได้เฉพาะไฟล์ที่ยังไม่ได้โอนเงินจริง หรือธนาคารปฏิเสธเท่านั้น ถ้าเงินออกจากบัญชีไปแล้วห้ามยกเลิก เพราะรอบหน้าจะจ่ายซ้ำ`,
    voidReason: "เหตุผลในการยกเลิก",
    voidReasonHint: "ต้องกรอก — อีกหกเดือนจะได้รู้ว่ายกเลิกเพราะอะไร ไม่ใช่กดพลาด (ไม่เกิน 500 ตัวอักษร)",
    voidReasonPlaceholder: "เช่น ธนาคารปฏิเสธไฟล์ / บัญชีบริษัทเงินไม่พอ / สร้างไฟล์ผิดรอบ",
    voidConfirm: "ยืนยันยกเลิกไฟล์",
    keepFile: "เก็บไฟล์นี้ไว้",
    voidedReasonPrefix: "เหตุผล",
    cancel: "ยกเลิก",
    actionError: "ทำรายการไม่สำเร็จ",
    listSummary: (from, to, total) => `แสดง ${from}–${to} จาก ${total} ไฟล์`,

    detail: {
      viewItems: "ดูงานในไฟล์",
      title: "งานที่จ่ายด้วยไฟล์นี้",
      subtitle: (fileRef) => `รหัสไฟล์ ${fileRef}`,
      loading: "กำลังโหลดรายการ…",
      error: "โหลดรายการในไฟล์ไม่สำเร็จ",
      empty: "ไฟล์นี้ไม่มีรายการงาน",
      colGuard: "รปภ",
      colJobs: "งาน",
      colIncome: "เงินได้",
      colWht: "หัก ณ ที่จ่าย",
      colTransfer: "โอนจริง",
      colState: "สถานะ",
      statePaid: "จ่ายแล้ว",
      stateReleased: "ดึงกลับเข้าคิวแล้ว",
      releaseIntro:
        "ใช้เมื่อธนาคาร “รับไฟล์” แล้ว แต่โอนให้ รปภ บางคนไม่สำเร็จ (เจอบ่อยสุดคือปลายทางยังไม่ได้ผูกพร้อมเพย์) — ติ๊กเฉพาะคนที่เงินไม่เข้า แล้วดึงงานของคนนั้นกลับเข้าคิวรอจ่าย คนอื่นในไฟล์ยังนับว่าจ่ายแล้วตามเดิม และสถานะของไฟล์ไม่เปลี่ยน",
      selectGuard: "เลือก",
      selectAll: "เลือกทั้งหมด",
      selectedSummary: (guards, jobs, amount) =>
        `เลือกไว้ ${guards} คน · ${jobs} งาน · ฿${amount}`,
      nothingSelected: "ติ๊กเลือก รปภ ที่ธนาคารโอนไม่สำเร็จอย่างน้อย 1 คน",
      releaseWarning:
        "งานของคนที่เลือกจะกลับเข้าคิว “รอจ่าย” และจะถูกจ่ายอีกครั้งในไฟล์รอบถัดไป — ถ้าจริง ๆ แล้วเงินเข้าบัญชีเขาไปแล้ว เท่ากับจ่ายซ้ำ กรุณาตรวจกับรายงานผลของธนาคารก่อน",
      releaseReason: "เหตุผลที่ดึงงานกลับ",
      releaseReasonHint: "ต้องกรอก — บันทึกไว้ว่าทำไมงานที่ระบบบอกว่าจ่ายแล้วถึงกลับมารอจ่ายอีก (ไม่เกิน 500 ตัวอักษร)",
      releaseReasonPlaceholder: "เช่น ธนาคารแจ้งโอนไม่สำเร็จ: ปลายทางไม่ได้ผูกพร้อมเพย์",
      releaseBtn: "ดึงงานกลับเข้าคิวรอจ่าย",
      releasing: "กำลังดึงกลับ…",
      releasedFlash: (guards) => `ดึงงานของ รปภ ${guards} คนกลับเข้าคิวแล้ว`,
      releaseError: "ดึงงานกลับไม่สำเร็จ",
      tooMany: (max) => `ดึงกลับได้ไม่เกิน ${max} งานต่อครั้ง — กรุณาแบ่งเลือกเป็นหลายรอบ`,
      close: "ปิด",
    },
  },
  en: {
    title: "Guard payout (SCB upload file)",
    subtitle:
      "Aggregate the unpaid backlog of finished guard jobs → generate the SCB Business Net upload file (PromptPay + ภ.ง.ด.53 WHT).",
    settings: "Payout settings",
    debitAccount: "Company debit account",
    feeDebitAccount: "Fee debit account (blank = use debit account)",
    revenueAccount: "Company revenue account (destination of the platform-cut sweep)",
    revenueAccountHint:
      "Used ONLY by the “platform cut” (OAT) file — not by the guard-payout or refund files. Must be a 10-digit SCB account with a valid check digit; it is checked on save and again at export. Until it is set, the sweep file cannot be generated.",
    whtRate: "Withholding rate (%)",
    whtForm: "WHT form (ภ.ง.ด.)",
    whtFormLabels: {
      "01": "01 — ภ.ง.ด.1ก",
      "03": "03 — ภ.ง.ด.2",
      "04": "04 — ภ.ง.ด.3",
      "11": "11 — ภ.ง.ด.1ก พิเศษ",
      "12": "12 — ภ.ง.ด.2ก",
      "13": "13 — ภ.ง.ด.3ก",
      "53": "53 — ภ.ง.ด.53",
    },
    whtFormHint: "ภ.ง.ด.3 for individuals · ภ.ง.ด.53 for juristic persons (companies)",
    whtFormUnknown: (code) => `${code} — not a code SCB accepts (pick another)`,
    whtFormUnset: "— not set —",
    incomeType: "Income type",
    incomeDesc: "Income description",
    feeCharge: "Who pays the transfer fee",
    feeChargeLabels: {
      OUR: "OUR — the company pays the fee (recommended)",
      BEN: "BEN — the fee is deducted from the guard's transfer",
    },
    feeChargeHint:
      "BEN makes the bank take its fee out of the credit, so the guard receives LESS than the transfer amount our ledger records as paid — our books and the bank's disagree from then on. Use OUR unless finance says otherwise.",
    smsNotify: "Let the bank SMS the guard",
    smsNotifyHint:
      "On = the guard's phone number is written into the file so SCB can text them about the transfer; the bank bills per message. Off = the number is not sent at all (the transfer is unaffected — the PromptPay destination is unchanged).",
    smsNotifyOn: "On — the guard's phone goes in the file",
    smsNotifyOff: "Off — no phone number in the file",
    maxTransfer: "Per-transfer cap (THB)",
    maxTransferHint:
      "A guard whose total transfer exceeds this is EXCLUDED from the file (they appear under “cannot pay”), never truncated — their jobs stay in the backlog. Default 2,000,000 (the PromptPay/ORFT per-transaction limit). Blank = keep the stored value; it cannot be cleared from here.",
    save: "Save settings",
    saved: "Saved",
    preview: "Payout preview",
    refresh: "Refresh",
    dateFrom: "Jobs finished from",
    dateTo: "to",
    applyFilter: "Apply filter",
    clearFilter: "Clear filter",
    selectAll: "Select all",
    selectOne: "Select",
    pickSomeone: "No guards ticked — select at least one to generate the file",
    selectedOnly: "selected only",
    ofTotal: (total) => `of ${total} payable`,
    guard: "Guard",
    proxy: "PromptPay",
    income: "Income",
    wht: "WHT",
    transfer: "Transfer",
    totalTransfer: "Total transfer",
    totalWht: "Total WHT",
    recipients: "Recipients",
    excludedTitle: "Cannot pay (fix the profile first)",
    excludedHint:
      "Click a guard id to fill in the missing national id / bank details, then come back and refresh — their jobs stay in the backlog, nothing is lost.",
    fixGuard: "Fix this guard's payout details",
    reason: "Reason",
    jobs: "jobs",
    nobody: "No unpaid payouts right now",
    exportBtn: "Generate SCB upload file",
    exporting: "Generating…",
    exportHint:
      "One file pays many guards — one transfer line per guard (all their jobs summed). Downloads a .txt and marks ONLY the selected guards' jobs as paid (prevents double-pay); unticked guards stay in the next run.",
    loadError: "Failed to load",
    saveError: "Failed to save",
    exportError: "Failed to generate the file",
    nothingToPay: "Nothing payable right now",

    history: "Generated files",
    historyHint:
      "Every payout file generated so far, newest first — re-download one whose copy was lost, and record whether the bank took it.",
    historyEmpty: "No payout file has been generated yet",
    historyError: "Failed to load the file history",
    fileRef: "File ref (SCB)",
    valueDate: "Value date",
    people: "Guards",
    totalAmount: "Total",
    status: "Status",
    createdAt: "Generated",
    actions: "Actions",
    statusLabels: {
      generated: "File generated",
      uploaded: "Uploaded to the bank",
      confirmed: "Bank confirmed",
      rejected: "Bank rejected",
      voided: "Voided",
    },
    stepLabels: {
      uploaded: "Mark uploaded",
      confirmed: "Bank confirmed",
      rejected: "Bank rejected",
    },
    redownload: "Download again",
    noStoredFile: "Generated before file copies were kept — it cannot be re-downloaded",
    downloadError: "Failed to download the file",
    recordTitle: (step) => `Record: ${step}`,
    recordBody: (step) =>
      `Record that this file was “${step}”. This only writes down what actually happened at the bank — nothing is sent to SCB and no amount changes.`,
    confirmedWarning:
      "This step cannot be undone — only take it once you have seen the money leave the company account. Afterwards the whole file can no longer be voided and every job in it stays marked paid, permanently; confirming the wrong row, or confirming before the bank actually settles, does not put that work back in the queue by itself. What is still open to you: if the bank failed some individual transfers, open “View jobs” on this row and release those guards one by one.",
    noteLabel: "Note (optional)",
    noteHint: "e.g. the bank's own message back — 500 characters max",
    voidBtn: "Void file",
    voidTitle: "Void this payout file?",
    voidWarning: (recipients, amount) =>
      `Every job in this file (${recipients} guards · ฿${amount}) goes back into the payable queue and can be paid again by the next file. Only void a file the bank never took, or refused. If the money already left the account, do NOT void it — the next run would pay those guards a second time.`,
    voidReason: "Reason for voiding",
    voidReasonHint:
      "Required — six months from now this is what tells a void apart from a mis-click (500 characters max)",
    voidReasonPlaceholder: "e.g. bank refused the file / not enough funds / wrong period",
    voidConfirm: "Void the file",
    keepFile: "Keep the file",
    voidedReasonPrefix: "Reason",
    cancel: "Cancel",
    actionError: "The action failed",
    listSummary: (from, to, total) => `Showing ${from}–${to} of ${total} files`,

    detail: {
      viewItems: "View jobs",
      title: "Jobs this file paid",
      subtitle: (fileRef) => `File ref ${fileRef}`,
      loading: "Loading the file's jobs…",
      error: "Failed to load the jobs in this file",
      empty: "This file has no job rows",
      colGuard: "Guard",
      colJobs: "Jobs",
      colIncome: "Income",
      colWht: "WHT",
      colTransfer: "Transfer",
      colState: "State",
      statePaid: "Paid",
      stateReleased: "Back in the queue",
      releaseIntro:
        "For when the bank ACCEPTED the file but a particular transfer bounced — an unregistered PromptPay proxy is the everyday cause. Tick only the guards whose money never arrived and release their jobs back into the payable queue; everyone else in the file stays paid and the file's own status is untouched.",
      selectGuard: "Select",
      selectAll: "Select all",
      selectedSummary: (guards, jobs, amount) =>
        `${guards} guards · ${jobs} jobs · ฿${amount} selected`,
      nothingSelected: "Tick at least one guard whose transfer the bank could not deliver",
      releaseWarning:
        "The selected guards' jobs go back into the payable queue and will be paid again by the next file — if the money did in fact reach them, that is a second payment. Check the bank's result report first.",
      releaseReason: "Why these are going back",
      releaseReasonHint:
        "Required — it is the record of why money the ledger says was paid is queued to be paid again (500 characters max)",
      releaseReasonPlaceholder: "e.g. bank reported the credit failed: PromptPay proxy not registered",
      releaseBtn: "Release back to the queue",
      releasing: "Releasing…",
      releasedFlash: (guards) => `Released ${guards} guards' jobs back into the queue`,
      releaseError: "Failed to release those jobs",
      tooMany: (max) => `At most ${max} jobs can be released at once — do it in several passes`,
      close: "Close",
    },
  },
};
