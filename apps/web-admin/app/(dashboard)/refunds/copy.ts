import type { components } from "@/api/generated/payment";
import type { Lang } from "@/lib/lang";

/**
 * The five lifecycle states a generated REFUND file can be in, taken FROM the contract rather than
 * re-typed here (`services/payment/src/domain/batch_status.rs` › `BatchStatus`, shared with the
 * payout stream). Used as the key of `statusLabels` below, so the day a sixth state is added to the
 * OpenAPI enum the build breaks until BOTH locales name it — a status an admin reads as a raw
 * `"partially_settled"` is worse than no status at all on a money screen.
 */
export type RefundBatchStatusValue = components["schemas"]["RefundBatch"]["status"];

/**
 * The steps `POST /admin/refunds/batches/{id}/status` accepts — deliberately derived from the
 * REQUEST schema, not from `RefundBatchStatusValue`. `generated` (only ever the initial state) and
 * `voided` (its own endpoint, because it must also un-mark every obligation and carry a reason) are
 * not in this union, so the UI cannot offer a button the endpoint would answer with a 400.
 */
export type RefundBatchStep = components["schemas"]["SetRefundBatchStatusRequest"]["status"];

/**
 * WHICH table owes the obligation — the pair `(source_kind, source_id)` is how the release endpoint
 * names one, because `payment.payments` and `payment.payment_slips` are separate tables with
 * separate id spaces. Taken from the contract so a third lane forces a label in both locales.
 */
export type RefundSourceKind = components["schemas"]["RefundSourceKind"];

/**
 * How many customers ONE export may name (`MAX_SELECTED_CUSTOMERS`,
 * `services/payment/src/domain/refund_export.rs`). Mirrored so an over-long tick list is caught at
 * the keyboard with a "split it into several files" message instead of coming back as a 400 that
 * refunded nobody.
 */
export const MAX_SELECTED_CUSTOMERS = 500;

/**
 * How many obligations ONE per-customer release may name (`MAX_VOIDED_REFUND_ITEMS`, same module).
 * The endpoint is all-or-nothing, so an over-cap call releases NOTHING and the admin would be left
 * guessing which half failed — caught before the round-trip.
 */
export const MAX_RELEASE_SOURCES = 500;

/** Page copy for the customer-refund (SCB export) screen — Thai default, English parity. */
export const COPY: Record<
  Lang,
  {
    title: string;
    subtitle: string;

    // ── Where the money and the destination come from ───────────────────────────────────
    /** The two lanes this screen settles, said plainly — an admin has to know what they are
     *  about to send back before they send it. */
    scopeNote: string;
    /** The debit account / fee-charge code are the PAYOUT screen's settings, shared by both
     *  streams; this screen deliberately has no second copy of that form. */
    configNote: string;
    configLink: string;
    /** No ภ.ง.ด. anywhere: a refund is the customer's own money returning, not income. */
    noWhtNote: string;

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
    customer: string;
    proxy: string;
    obligations: string;
    amount: string;
    totalAmount: string;
    recipients: string;
    /** Hit when more customers are ticked than one file may carry (`MAX_SELECTED_CUSTOMERS`). */
    tooManyCustomers: (max: number) => string;
    excludedTitle: string;
    /** What an admin can actually DO about an excluded row — there is no admin-editable field
     *  behind it, so the honest answer is where the destination comes from and that nothing is
     *  lost. Deliberately not a deep link: `/customers` takes no id parameter, and a link that
     *  silently lands on an unfiltered list is worse than plain text. */
    excludedHint: string;
    reason: string;
    nobody: string;
    exportBtn: string;
    exporting: string;
    exportHint: string;
    loadError: string;
    exportError: string;

    // ── Batch history: what happened to the files we already generated ──────────────────
    history: string;
    historyHint: string;
    historyEmpty: string;
    historyError: string;
    fileRef: string;
    valueDate: string;
    people: string;
    status: string;
    createdAt: string;
    actions: string;
    /** Lifecycle state names. Thai mirrors `BatchStatus::label_th()` word for word so the badge
     *  and the server's own 409 message ("ไฟล์นี้อยู่ในสถานะ …") never disagree. */
    statusLabels: Record<RefundBatchStatusValue, string>;
    /** Button labels — the step being RECORDED ("mark uploaded"), not the state's name. */
    stepLabels: Record<RefundBatchStep, string>;
    redownload: string;
    /** Tooltip on a disabled re-download (a batch whose text was not stored). */
    noStoredFile: string;
    downloadError: string;
    recordTitle: (step: string) => string;
    /**
     * Body for the REVERSIBLE steps only (`uploaded`, `rejected`). Its reassurance ("nothing is
     * sent to SCB, no amount changes") is true for those two and dangerously false for
     * `confirmed`, which is why that step has its own [confirmedWarning] instead of sharing this.
     */
    recordBody: (step: string) => string;
    /** Body for the `confirmed` step — the one-way door. Names the recourse that DOES survive
     *  (the per-customer release) rather than overstating the finality. */
    confirmedWarning: string;
    noteLabel: string;
    noteHint: string;
    voidBtn: string;
    voidTitle: string;
    /** The consequence, in plain words — the sentence that has to stop a mis-click. */
    voidWarning: (recipients: number, amount: string) => string;
    voidReason: string;
    voidReasonHint: string;
    voidReasonPlaceholder: string;
    voidConfirm: string;
    /** The void modal's DISMISS button. Its own key because Thai "ยกเลิก" means both "dismiss this
     *  dialog" and "void the file" — next to "ยืนยันยกเลิกไฟล์" that is the one ambiguity on this
     *  screen we cannot afford. */
    keepFile: string;
    voidedReasonPrefix: string;
    cancel: string;
    actionError: string;
    listSummary: (from: number, to: number, total: number) => string;

    // ── Batch detail + per-customer release (batch-detail-modal.tsx) ────────────────────
    detail: {
      viewItems: string;
      title: string;
      subtitle: (fileRef: string) => string;
      loading: string;
      error: string;
      empty: string;
      colCustomer: string;
      colObligations: string;
      colKinds: string;
      colAmount: string;
      colState: string;
      /** Which table the obligation came from — the two lanes, named for a human. */
      sourceKindLabels: Record<RefundSourceKind, string>;
      /** Per-row state of the paid-marker: still settled, or handed back to the queue. */
      statePaid: string;
      stateReleased: string;
      /** Why this screen exists — the bank took the FILE but bounced ONE credit line. */
      releaseIntro: string;
      selectCustomer: string;
      selectAll: string;
      selectedSummary: (customers: number, obligations: number, amount: string) => string;
      nothingSelected: string;
      releaseWarning: string;
      releaseReason: string;
      releaseReasonHint: string;
      releaseReasonPlaceholder: string;
      releaseBtn: string;
      releasing: string;
      releasedFlash: (customers: number) => string;
      releaseError: string;
      /** The endpoint's own per-call cap (`MAX_VOIDED_REFUND_ITEMS`), hit before the round-trip. */
      tooMany: (max: number) => string;
      close: string;
    };
  }
> = {
  th: {
    title: "คืนเงินลูกค้า (ไฟล์อัปโหลด SCB)",
    subtitle:
      "รวมยอดที่ต้องคืนลูกค้าที่ยังไม่ได้คืน → สร้างไฟล์อัปโหลด SCB Business Net (พร้อมเพย์เบอร์ที่ลูกค้าสมัครไว้) ไฟล์เดียวคืนได้หลายคน",
    scopeNote:
      "รวม 2 ทาง: (1) ยอดคืนจากบิลงาน — จ่ายเกินตอนปิดงาน / ยกเลิกงาน / จ่ายซ้อนแล้วแพ้จังหวะ และ (2) โอนซ้ำ — ลูกค้าโอนสลิปที่ 2 เข้ามาทั้งที่บิลนั้นจ่ายแล้ว ลูกค้าคนเดียวที่ค้างหลายรายการจะถูกรวมเป็นการโอน 1 รายการ",
    configNote:
      "ใช้บัญชีตัดเงินบริษัทและผู้รับผิดชอบค่าธรรมเนียมชุดเดียวกับหน้า “จ่ายเงิน รปภ” — แก้ที่นั่นที่เดียว ไม่มีการตั้งค่าซ้ำในหน้านี้",
    configLink: "ไปหน้าตั้งค่าการจ่าย",
    noWhtNote:
      "ไม่มีหัก ณ ที่จ่ายในไฟล์นี้ — เงินคืนคือเงินของลูกค้าเอง ไม่ใช่เงินได้ ไฟล์จึงไม่มีใบรับรองหัก ณ ที่จ่าย และไม่ต้องตั้งค่า ภ.ง.ด.",

    preview: "พรีวิวรายการคืนเงิน",
    refresh: "รีเฟรช",
    dateFrom: "ยอดที่ค้างคืนตั้งแต่",
    dateTo: "ถึงวันที่",
    applyFilter: "ใช้ตัวกรอง",
    clearFilter: "ล้างตัวกรอง",
    selectAll: "เลือกทั้งหมด",
    selectOne: "เลือก",
    pickSomeone: "ยังไม่ได้เลือกลูกค้า — ติ๊กอย่างน้อย 1 คนเพื่อสร้างไฟล์",
    selectedOnly: "เฉพาะที่เลือก",
    ofTotal: (total) => `จากทั้งหมด ${total} คน`,
    customer: "ลูกค้า",
    proxy: "พร้อมเพย์",
    obligations: "จำนวนรายการ",
    amount: "ยอดคืน",
    totalAmount: "ยอดคืนรวม",
    recipients: "จำนวนผู้รับ",
    tooManyCustomers: (max) =>
      `ไฟล์เดียวคืนได้ไม่เกิน ${max} คน — กรุณาแบ่งเลือกเป็นหลายไฟล์`,
    excludedTitle: "คืนไม่ได้ (ต้องแก้ข้อมูลก่อน)",
    excludedHint:
      "ปลายทางพร้อมเพย์ใช้เบอร์ที่ลูกค้าสมัครไว้ในแอป แก้จากหน้าแอดมินไม่ได้ — ต้องให้ลูกค้าอัปเดตเบอร์/ผูกพร้อมเพย์เอง แล้วกลับมากดรีเฟรช ยอดของคนกลุ่มนี้ยังค้างอยู่ ไม่ได้หายไป",
    reason: "เหตุผล",
    nobody: "ไม่มียอดค้างคืนในขณะนี้",
    exportBtn: "สร้างไฟล์คืนเงิน SCB",
    exporting: "กำลังสร้างไฟล์…",
    exportHint:
      "ไฟล์เดียวคืนได้หลายคน — 1 ลูกค้า = 1 รายการโอน (รวมทุกยอดค้างของคนนั้น). กดแล้วจะดาวน์โหลดไฟล์ .txt และบันทึกเฉพาะคนที่เลือกว่าคืนแล้ว (กันคืนซ้ำ) คนที่ไม่ได้เลือกจะยังค้างอยู่ในรอบถัดไป",
    loadError: "โหลดข้อมูลไม่สำเร็จ",
    exportError: "สร้างไฟล์ไม่สำเร็จ",

    history: "ประวัติไฟล์คืนเงิน",
    historyHint:
      "ไฟล์คืนเงินที่สร้างไปแล้วทั้งหมด (ใหม่สุดอยู่บน) — ดาวน์โหลดซ้ำได้ถ้าไฟล์เดิมหาย และบันทึกได้ว่าธนาคารรับหรือปฏิเสธ",
    historyEmpty: "ยังไม่เคยสร้างไฟล์คืนเงิน",
    historyError: "โหลดประวัติไฟล์ไม่สำเร็จ",
    fileRef: "รหัสไฟล์ (SCB)",
    valueDate: "วันที่เงินเข้า",
    people: "จำนวนคน",
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
    noStoredFile: "ไฟล์นี้ไม่ได้เก็บสำเนาไว้ จึงดาวน์โหลดซ้ำไม่ได้",
    downloadError: "ดาวน์โหลดไฟล์ไม่สำเร็จ",
    recordTitle: (step) => `บันทึกสถานะ: ${step}`,
    recordBody: (step) =>
      `บันทึกว่าไฟล์นี้ “${step}” — เป็นการบันทึกสิ่งที่เกิดขึ้นจริงที่ธนาคาร ไม่ได้ส่งอะไรไปที่ SCB และไม่กระทบยอดเงิน`,
    confirmedWarning:
      "ขั้นนี้ย้อนกลับไม่ได้ กดเมื่อเห็นเงินออกจากบัญชีบริษัทจริงแล้วเท่านั้น — หลังกดจะ “ยกเลิกทั้งไฟล์” ไม่ได้อีก และยอดคืนทุกรายการในไฟล์นี้จะถูกนับว่าคืนแล้วถาวร ถ้ากดผิดไฟล์หรือกดก่อนเงินออกจริง ยอดกลุ่มนั้นจะไม่กลับเข้าคิวรอคืนเอง · ทางออกที่ยังเหลืออยู่: ถ้าธนาคารโอนไม่สำเร็จบางราย ให้เปิด “ดูรายการในไฟล์” แล้วดึงกลับเป็นรายคน",
    noteLabel: "หมายเหตุ (ไม่บังคับ)",
    noteHint: "เช่น ข้อความที่ธนาคารตอบกลับมา — ไม่เกิน 500 ตัวอักษร",
    voidBtn: "ยกเลิกไฟล์",
    voidTitle: "ยกเลิกไฟล์คืนเงินนี้?",
    voidWarning: (recipients, amount) =>
      `ยอดคืนทั้งหมดในไฟล์นี้ (ลูกค้า ${recipients} คน · ฿${amount}) จะกลับเข้าคิว “รอคืน” และคืนใหม่ได้ในไฟล์รอบถัดไป — ยกเลิกได้เฉพาะไฟล์ที่ยังไม่ได้โอนเงินจริง หรือธนาคารปฏิเสธเท่านั้น ถ้าเงินออกจากบัญชีไปแล้วห้ามยกเลิก เพราะรอบหน้าจะคืนซ้ำ`,
    voidReason: "เหตุผลในการยกเลิก",
    voidReasonHint:
      "ต้องกรอก — อีกหกเดือนจะได้รู้ว่ายกเลิกเพราะอะไร ไม่ใช่กดพลาด (ไม่เกิน 500 ตัวอักษร)",
    voidReasonPlaceholder: "เช่น ธนาคารปฏิเสธไฟล์ / บัญชีบริษัทเงินไม่พอ / สร้างไฟล์ผิดรอบ",
    voidConfirm: "ยืนยันยกเลิกไฟล์",
    keepFile: "เก็บไฟล์นี้ไว้",
    voidedReasonPrefix: "เหตุผล",
    cancel: "ยกเลิก",
    actionError: "ทำรายการไม่สำเร็จ",
    listSummary: (from, to, total) => `แสดง ${from}–${to} จาก ${total} ไฟล์`,

    detail: {
      viewItems: "ดูรายการในไฟล์",
      title: "ยอดคืนที่จ่ายด้วยไฟล์นี้",
      subtitle: (fileRef) => `รหัสไฟล์ ${fileRef}`,
      loading: "กำลังโหลดรายการ…",
      error: "โหลดรายการในไฟล์ไม่สำเร็จ",
      empty: "ไฟล์นี้ไม่มีรายการคืนเงิน",
      colCustomer: "ลูกค้า",
      colObligations: "รายการ",
      colKinds: "ที่มา",
      colAmount: "ยอดคืน",
      colState: "สถานะ",
      sourceKindLabels: {
        payment: "ยอดคืนจากบิลงาน",
        slip: "โอนซ้ำ (สลิปเกิน)",
      },
      statePaid: "คืนแล้ว",
      stateReleased: "ดึงกลับเข้าคิวแล้ว",
      releaseIntro:
        "ใช้เมื่อธนาคาร “รับไฟล์” แล้ว แต่โอนคืนลูกค้าบางคนไม่สำเร็จ (เจอบ่อยสุดคือปลายทางยังไม่ได้ผูกพร้อมเพย์) — ติ๊กเฉพาะคนที่เงินไม่เข้า แล้วดึงยอดของคนนั้นกลับเข้าคิวรอคืน คนอื่นในไฟล์ยังนับว่าคืนแล้วตามเดิม และสถานะของไฟล์ไม่เปลี่ยน",
      selectCustomer: "เลือก",
      selectAll: "เลือกทั้งหมด",
      selectedSummary: (customers, obligations, amount) =>
        `เลือกไว้ ${customers} คน · ${obligations} รายการ · ฿${amount}`,
      nothingSelected: "ติ๊กเลือกลูกค้าที่ธนาคารโอนคืนไม่สำเร็จอย่างน้อย 1 คน",
      releaseWarning:
        "ยอดของคนที่เลือกจะกลับเข้าคิว “รอคืน” และจะถูกคืนอีกครั้งในไฟล์รอบถัดไป — ถ้าจริง ๆ แล้วเงินเข้าบัญชีเขาไปแล้ว เท่ากับคืนซ้ำ กรุณาตรวจกับรายงานผลของธนาคารก่อน",
      releaseReason: "เหตุผลที่ดึงรายการกลับ",
      releaseReasonHint:
        "ต้องกรอก — บันทึกไว้ว่าทำไมยอดที่ระบบบอกว่าคืนแล้วถึงกลับมารอคืนอีก (ไม่เกิน 500 ตัวอักษร)",
      releaseReasonPlaceholder: "เช่น ธนาคารแจ้งโอนไม่สำเร็จ: ปลายทางไม่ได้ผูกพร้อมเพย์",
      releaseBtn: "ดึงรายการกลับเข้าคิวรอคืน",
      releasing: "กำลังดึงกลับ…",
      releasedFlash: (customers) => `ดึงยอดของลูกค้า ${customers} คนกลับเข้าคิวแล้ว`,
      releaseError: "ดึงรายการกลับไม่สำเร็จ",
      tooMany: (max) => `ดึงกลับได้ไม่เกิน ${max} รายการต่อครั้ง — กรุณาแบ่งเลือกเป็นหลายรอบ`,
      close: "ปิด",
    },
  },
  en: {
    title: "Customer refunds (SCB upload file)",
    subtitle:
      "Aggregate the money customers are still owed → generate the SCB Business Net upload file (PromptPay to the phone they registered with). One file refunds many customers.",
    scopeNote:
      "Two lanes are covered: (1) money owed on a booking bill — an overpay reconciled at completion, a cancellation refund, or the race-lost pre-payment; and (2) a duplicate transfer — a second verified slip for a bill that was already paid. A customer owed several is one transfer line.",
    configNote:
      "The company debit account and who pays the transfer fee are the SAME settings the guard-payout screen owns — edit them there; this screen deliberately keeps no second copy of that form.",
    configLink: "Open payout settings",
    noWhtNote:
      "No withholding tax in this file — a refund is the customer's own money coming back, not assessable income, so the file carries no WHT certificate and needs no ภ.ง.ด. setting.",

    preview: "Refund preview",
    refresh: "Refresh",
    dateFrom: "Owed from",
    dateTo: "to",
    applyFilter: "Apply filter",
    clearFilter: "Clear filter",
    selectAll: "Select all",
    selectOne: "Select",
    pickSomeone: "No customers ticked — select at least one to generate the file",
    selectedOnly: "selected only",
    ofTotal: (total) => `of ${total} refundable`,
    customer: "Customer",
    proxy: "PromptPay",
    obligations: "Items",
    amount: "Refund",
    totalAmount: "Total refund",
    recipients: "Recipients",
    tooManyCustomers: (max) =>
      `At most ${max} customers fit in one file — split the selection across several files`,
    excludedTitle: "Cannot refund (fix the details first)",
    excludedHint:
      "The PromptPay destination is the phone the customer registered with in the app; it cannot be edited from the admin — the customer has to update it (and link PromptPay) themselves. Then come back and refresh. Their money stays in the queue, nothing is lost.",
    reason: "Reason",
    nobody: "Nothing is owed back right now",
    exportBtn: "Generate SCB refund file",
    exporting: "Generating…",
    exportHint:
      "One file refunds many customers — one transfer line per customer (all their pending items summed). Downloads a .txt and marks ONLY the selected customers' items as refunded (prevents double-refund); unticked customers stay in the next run.",
    loadError: "Failed to load",
    exportError: "Failed to generate the file",

    history: "Generated refund files",
    historyHint:
      "Every refund file generated so far, newest first — re-download one whose copy was lost, and record whether the bank took it.",
    historyEmpty: "No refund file has been generated yet",
    historyError: "Failed to load the file history",
    fileRef: "File ref (SCB)",
    valueDate: "Value date",
    people: "Customers",
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
    noStoredFile: "No copy of this file was stored — it cannot be re-downloaded",
    downloadError: "Failed to download the file",
    recordTitle: (step) => `Record: ${step}`,
    recordBody: (step) =>
      `Record that this file was “${step}”. This only writes down what actually happened at the bank — nothing is sent to SCB and no amount changes.`,
    confirmedWarning:
      "This step cannot be undone — only take it once you have seen the money leave the company account. Afterwards the whole file can no longer be voided and every refund in it stays marked returned, permanently; confirming the wrong row, or confirming before the bank actually settles, does not put that money back in the queue by itself. What is still open to you: if the bank failed some individual transfers, open “View items” on this row and release those customers one by one.",
    noteLabel: "Note (optional)",
    noteHint: "e.g. the bank's own message back — 500 characters max",
    voidBtn: "Void file",
    voidTitle: "Void this refund file?",
    voidWarning: (recipients, amount) =>
      `Every refund in this file (${recipients} customers · ฿${amount}) goes back into the refundable queue and can be sent again by the next file. Only void a file the bank never took, or refused. If the money already left the account, do NOT void it — the next run would refund those customers a second time.`,
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
      viewItems: "View items",
      title: "Refunds this file returned",
      subtitle: (fileRef) => `File ref ${fileRef}`,
      loading: "Loading the file's items…",
      error: "Failed to load the items in this file",
      empty: "This file has no refund rows",
      colCustomer: "Customer",
      colObligations: "Items",
      colKinds: "Source",
      colAmount: "Refund",
      colState: "State",
      sourceKindLabels: {
        payment: "Booking bill",
        slip: "Duplicate transfer",
      },
      statePaid: "Refunded",
      stateReleased: "Back in the queue",
      releaseIntro:
        "For when the bank ACCEPTED the file but a particular transfer bounced — an unregistered PromptPay proxy is the everyday cause. Tick only the customers whose money never arrived and release their items back into the refundable queue; everyone else in the file stays refunded and the file's own status is untouched.",
      selectCustomer: "Select",
      selectAll: "Select all",
      selectedSummary: (customers, obligations, amount) =>
        `${customers} customers · ${obligations} items · ฿${amount} selected`,
      nothingSelected: "Tick at least one customer whose refund the bank could not deliver",
      releaseWarning:
        "The selected customers' refunds go back into the queue and will be sent again by the next file — if the money did in fact reach them, that is a second refund. Check the bank's result report first.",
      releaseReason: "Why these are going back",
      releaseReasonHint:
        "Required — it is the record of why money the ledger says was refunded is queued to be sent again (500 characters max)",
      releaseReasonPlaceholder:
        "e.g. bank reported the credit failed: PromptPay proxy not registered",
      releaseBtn: "Release back to the queue",
      releasing: "Releasing…",
      releasedFlash: (customers) => `Released ${customers} customers' refunds back into the queue`,
      releaseError: "Failed to release those refunds",
      tooMany: (max) => `At most ${max} items can be released at once — do it in several passes`,
      close: "Close",
    },
  },
};
