import type { components } from "@/api/generated/payment";
import type { Lang } from "@/lib/lang";

/**
 * The five lifecycle states a generated SWEEP file can be in, taken FROM the contract rather than
 * re-typed here (`services/payment/src/domain/batch_status.rs` › `BatchStatus`, the ONE table all
 * three money streams walk). Used as the key of `statusLabels`, so the day a sixth state is added
 * to the OpenAPI enum the build breaks until BOTH locales name it — a status an admin reads as a
 * raw `"partially_settled"` is worse than no status at all on a money screen.
 *
 * Read straight off the schema with no `NonNullable`: `status` is `required` in the contract, so the
 * generated field is not optional and the union is already exactly the five states. Re-widening it
 * here would put `undefined` back into every `Record` key and re-introduce the "status missing"
 * branches the contract has ruled out.
 */
export type DeductionBatchStatusValue = components["schemas"]["DeductionBatch"]["status"];

/**
 * The steps `POST /admin/deductions/batches/{id}/status` accepts — deliberately derived from the
 * REQUEST schema, not from [DeductionBatchStatusValue]. `generated` (only ever the initial state)
 * and `voided` (its own endpoint, because it must also release every job and carry a reason) are
 * not in this union, so the UI cannot offer a button the endpoint would answer with a 400.
 */
export type DeductionBatchStep = components["schemas"]["SetDeductionBatchStatusRequest"]["status"];

/**
 * Why a job could not be priced, as a stable machine code (`SnapshotGap::code`). Keyed labels below
 * turn it into a heading an admin can group by; the server's own Thai `reason` is still shown per
 * row, because it is the sentence that says what to do about THAT job.
 */
export type ExcludedJobCode = components["schemas"]["ExcludedJob"]["code"];

/**
 * The five components a job's cut is built from — itemised, never a lump sum.
 *
 * This is the screen's whole reason for existing in the shape it has. `tip` and `unpaid_guard_share`
 * are in the platform's cut ONLY because of two known, deferred bugs (the customer is billed a
 * gratuity the guard never receives; a booking billed for N guards pays exactly one). Folding them
 * into "commission" would show an admin a number that looks like revenue and is really two defects,
 * and the day either is fixed the total moves with no visible reason. So they are listed, labelled,
 * and flagged — see [DEFERRED_BUG_COMPONENTS].
 *
 * Order is the reading order of the breakdown table: the two real components first, the two bugs
 * next, the rounding drift last (it is the only one that may be NEGATIVE).
 *
 * THESE FIVE ARE THE BILLED CUT, NOT THE TRANSFER. `uncollected` is deliberately NOT one of them:
 * it is not a source of money, it is the part of these bills the customer never actually paid, and
 * the contract SUBTRACTS it (`total_amount = billed_cut_total − uncollected_total`). Adding it to
 * this list would put a negative "component" in a column of positives and make the five stop summing
 * to `billed_cut_total`; it gets its own line under the table instead, where the subtraction is
 * visible arithmetic rather than a total that quietly disagrees with its own rows.
 */
export const CUT_COMPONENTS = [
  "commission",
  "cancellation_fee",
  "tip",
  "unpaid_guard_share",
  "rounding_adjustment",
] as const;
export type CutComponent = (typeof CUT_COMPONENTS)[number];

/** The components that exist only because of a DEFERRED bug, flagged in the breakdown. Fixing
 *  either one moves the figure beside it, and the flag is what announces that in advance. */
export const DEFERRED_BUG_COMPONENTS: readonly CutComponent[] = ["tip", "unpaid_guard_share"];

/**
 * How many jobs ONE per-item release may name (`MAX_VOIDED_DEDUCTION_ITEMS`,
 * `services/payment/src/domain/deduction.rs`). The endpoint is all-or-nothing, so an over-cap call
 * releases NOTHING and the admin would be left guessing which half failed — caught before the
 * round-trip.
 */
export const MAX_RELEASE_JOBS = 500;

/** Ledger / register rows per page — these tables are client-paged (the API returns one capped
 *  block, not a server-paged list), so this is purely how much is put on screen at once. */
export const LEDGER_PAGE_SIZE = 25;

/** Page copy for the platform-cut (ยอดหักเข้าระบบ) screen — Thai default, English parity. */
export const COPY: Record<
  Lang,
  {
    title: string;
    subtitle: string;

    // ── What this file IS, said before anything else ────────────────────────────────────
    /** The one sentence that has to land: this credits the COMPANY's own account. It is not a
     *  payment to a third party, and it must not be confused with the other two SCB files. */
    oatIntro: string;
    /** What the cut is made of, in words, before the numbers. */
    scopeNote: string;
    /** VAT + withheld WHT are the Revenue Department's money and are deliberately NOT swept. */
    taxNote: string;
    /** Where the destination account is configured (the payout screen owns the one config row). */
    configNote: string;
    configLink: string;
    /** The destination, masked to its last 4 — shown so an admin can check it before exporting. */
    destination: string;
    /** No revenue account configured yet: the export cannot run, and this is why + where to fix. */
    noDestination: string;

    // ── 1. The cut, itemised ────────────────────────────────────────────────────────────
    cutPanel: string;
    cutPanelHint: string;
    refresh: string;
    dateFrom: string;
    dateTo: string;
    dateHint: string;
    applyFilter: string;
    clearFilter: string;
    jobs: string;
    totalCut: string;
    totalCutCaption: string;
    inWindow: string;
    breakdown: string;
    component: string;
    amount: string;

    // ── The arithmetic under the breakdown ──────────────────────────────────────────────
    // The five components no longer ARE the transfer. `billed_cut_total − uncollected_total =
    // total_amount`, and all three are shown, because the difference is money the platform genuinely
    // earned on a bill the customer never fully paid: silently shrinking the figure would leave an
    // admin reconciling a transfer against a number with an unexplained hole in it.
    /** Σ of the five components — what the settled BILLS earned, before asking what was received. */
    billedCut: string;
    billedCutNote: string;
    /** The billed-but-never-received part, SUBTRACTED from the transfer. */
    uncollected: string;
    uncollectedNote: string;
    /** Badge on the uncollected line — the one-word version of "deliberately left out of the file". */
    uncollectedBadge: string;
    /** The bottom line of the same arithmetic: what the file will actually move. */
    netToSweep: string;
    netToSweepNote: string;
    /** Raised only when there IS uncollected money — the full explanation of why it is not swept. */
    uncollectedCallout: string;
    /** Column header for the same figure on the per-job ledger (short enough for a table head). */
    uncollectedShort: string;
    /** `Record<CutComponent, …>` so a sixth component in the contract forces a label in BOTH
     *  locales rather than rendering as a blank row on a money screen. */
    componentLabels: Record<CutComponent, string>;
    /** WHY each component contributes what it does — the sentence an accountant needs. */
    componentNotes: Record<CutComponent, string>;
    /** The same five, short enough to be a TABLE HEADER. The per-job ledger puts all five side by
     *  side; the full Thai labels there would make one row wider than any screen, and a table an
     *  operator has to scroll sideways to read is a table they will not check. */
    componentShort: Record<CutComponent, string>;
    /** Badge on the two components that are really deferred bugs. */
    deferredBugBadge: string;
    nothingToSweep: string;

    // ── The money in the same account that is NOT ours ───────────────────────────────────
    notSweptTitle: string;
    notSweptIntro: string;
    vatNotSwept: string;
    vatNotSweptNote: string;
    guardIncomeNotSwept: string;
    guardIncomeNotSweptNote: string;

    // ── Excluded jobs ───────────────────────────────────────────────────────────────────
    excludedTitle: string;
    excludedIntro: string;
    /** Shown when the excluded list itself was truncated (`excluded_count` > rows returned). */
    excludedTruncated: (shown: number, total: number) => string;
    excludedCodeLabels: Record<ExcludedJobCode, string>;
    reason: string;
    booking: string;
    payment: string;

    // ── The per-job ledger ──────────────────────────────────────────────────────────────
    ledgerTitle: string;
    ledgerIntro: string;
    ledgerTruncated: (shown: number, total: number) => string;
    settledOn: string;
    listSummary: (from: number, to: number, total: number) => string;

    // ── 2. The OAT sweep file ───────────────────────────────────────────────────────────
    exportPanel: string;
    exportPanelHint: string;
    /** The whole-window rule: there is no tick list, and here is why. */
    exportHint: string;
    exportBtn: string;
    exporting: string;
    exportError: string;
    loadError: string;
    /** Why a preview can FAIL rather than come back short — the server refuses an over-wide window
     *  instead of truncating a money total, and the remedy is a narrower one. Shown under whatever
     *  the server itself said, because only the server knows which of the two 400s this was. */
    loadErrorWindowHint: string;
    /** Jobs in the window, but nothing transferable: the uncollected extras and the negative rounding
     *  cancelled the cut out. The remedy is the OPPOSITE of the too-wide one — a WIDER window. */
    netNotPositive: string;

    // ── Batch history ───────────────────────────────────────────────────────────────────
    history: string;
    historyHint: string;
    historyEmpty: string;
    historyError: string;
    fileRef: string;
    valueDate: string;
    jobCount: string;
    creditedTo: string;
    status: string;
    createdAt: string;
    actions: string;
    /** Lifecycle state names. Thai mirrors `BatchStatus::label_th()` word for word so the badge and
     *  the server's own 409 message ("ไฟล์นี้อยู่ในสถานะ …") never disagree. */
    statusLabels: Record<DeductionBatchStatusValue, string>;
    /** Button labels — the step being RECORDED ("mark uploaded"), not the state's name. */
    stepLabels: Record<DeductionBatchStep, string>;
    redownload: string;
    noStoredFile: string;
    downloadError: string;
    recordTitle: (step: string) => string;
    /** Body for the REVERSIBLE steps only (`uploaded`, `rejected`). */
    recordBody: (step: string) => string;
    /** Body for `confirmed` — the one-way door, same warning the other two screens carry. */
    confirmedWarning: string;
    noteLabel: string;
    noteHint: string;
    voidBtn: string;
    voidTitle: string;
    voidWarning: (jobs: number, amount: string) => string;
    voidReason: string;
    voidReasonHint: string;
    voidReasonPlaceholder: string;
    voidConfirm: string;
    /** The void modal's DISMISS button — its own key because Thai "ยกเลิก" means both "dismiss this
     *  dialog" and "void the file". */
    keepFile: string;
    voidedReasonPrefix: string;
    cancel: string;
    actionError: string;

    // ── Batch detail + per-job release ──────────────────────────────────────────────────
    detail: {
      viewItems: string;
      title: string;
      subtitle: (fileRef: string) => string;
      loading: string;
      error: string;
      empty: string;
      /** Why releasing a job here is NOT like releasing a failed credit line on the other two
       *  screens: the money already moved as one lump, so a release leaves the account OVER-swept. */
      releaseIntro: string;
      colBooking: string;
      colComponents: string;
      colUncollected: string;
      colAmount: string;
      colState: string;
      stateSwept: string;
      stateReleased: string;
      /** Heading of the block that REPLACES the tick list on a confirmed sweep. */
      confirmedTitle: string;
      /** Why the release is refused here and offered on the other two screens, plus the two remedies
       *  that are actually open — the client-side twin of the server's 409
       *  `DEDUCTION_BATCH_CONFIRMED`, so the control is never a click into an error. */
      confirmedNoRelease: string;
      selectJob: string;
      selectAll: string;
      selectedSummary: (jobs: number, amount: string) => string;
      nothingSelected: string;
      releaseWarning: string;
      releaseReason: string;
      releaseReasonHint: string;
      releaseReasonPlaceholder: string;
      releaseBtn: string;
      releasing: string;
      releasedFlash: (jobs: number) => string;
      releaseError: string;
      tooMany: (max: number) => string;
      close: string;
    };

    // ── 3. The two tax reports ──────────────────────────────────────────────────────────
    reports: {
      title: string;
      hint: string;
      /** The label that must stop anyone reading these as bank files. */
      notATransfer: string;
      month: string;
      monthHint: string;
      load: string;
      loading: string;
      loadError: string;
      csv: string;
      downloading: string;
      downloadError: string;
      notLoaded: string;
      empty: string;
      customer: string;

      vat: {
        title: string;
        hint: string;
        /** Which timestamp the report buckets on, and why it is not interchangeable. */
        basis: string;
        rows: string;
        subtotal: string;
        vat: string;
        total: string;
        colDate: string;
        colPayment: string;
        colBooking: string;
      };

      wht: {
        title: string;
        hint: string;
        basis: string;
        /** The stored ภ.ง.ด. form code is the operator's TAX decision — reported, never corrected. */
        formLabel: string;
        formHint: string;
        incomeTypeLabel: string;
        /** Where the form / income-type / rate are edited — a stated tax setting is useless if the
         *  admin cannot find the box it came out of. */
        settingsNote: string;
        payees: string;
        income: string;
        wht: string;
        colGuard: string;
        colTaxId: string;
        colAddress: string;
        colJobs: string;
        noTaxId: string;
        noName: string;
      };
    };
  }
> = {
  th: {
    title: "ยอดหักเข้าระบบ",
    subtitle:
      "ส่วนที่แพลตฟอร์มเก็บไว้จากงานที่ปิดบัญชีแล้ว → กวาดเข้าบัญชีรายได้บริษัทด้วยไฟล์ SCB (OAT) หนึ่งไฟล์ พร้อมรายงานภาษีที่ใช้ยื่นแบบ",

    oatIntro:
      "ไฟล์นี้ “โอนเข้าบัญชีบริษัทเอง” (ผลิตภัณฑ์ OAT — โอนระหว่างบัญชีตัวเอง) ไม่ใช่การจ่ายให้ใคร ต่างจากไฟล์จ่าย รปภ และไฟล์คืนเงินลูกค้าซึ่งโอนออกไปหาคนอื่น อย่าสลับไฟล์กันตอนอัปโหลดเข้า SCB",
    scopeNote:
      "สิ่งที่กวาด: ค่าคอมมิชชันที่หักจากค่าแรง รปภ · ค่ายกเลิกที่เก็บไว้ · ทิป · ส่วนของ รปภ. ที่ยังไม่ได้จ่าย (งานหลายคน) · ส่วนต่างจากการปัดเศษ — แยกให้เห็นทีละก้อนด้านล่าง",
    taxNote:
      "สิ่งที่ไม่กวาด และจะไม่กวาดจากที่นี่: VAT 7% และภาษีหัก ณ ที่จ่ายที่หักจาก รปภ. ทั้งสองก้อนเป็นเงินของกรมสรรพากรที่นั่งอยู่ในบัญชีเดียวกัน นำส่งด้วยการยื่นแบบ (ภ.พ.30 รายเดือน · ภ.ง.ด.3/53 ภายในวันที่ 7 ของเดือนถัดไป) ไม่ใช่ด้วยไฟล์โอนเงิน",
    configNote:
      "บัญชีตัดเงิน ผู้รับผิดชอบค่าธรรมเนียม และ “บัญชีรับรายได้บริษัท” (ปลายทางของไฟล์นี้) ตั้งอยู่ที่หน้าจ่ายเงิน รปภ ที่เดียว —",
    configLink: "ไปหน้าตั้งค่าการจ่าย",
    destination: "โอนเข้าบัญชี",
    noDestination:
      "ยังไม่ได้ตั้ง “บัญชีรับรายได้บริษัท” — สร้างไฟล์กวาดยอดไม่ได้จนกว่าจะตั้งค่า ตั้งได้ที่หน้าตั้งค่าการจ่าย",

    cutPanel: "ยอดหักเข้าระบบในช่วงที่เลือก",
    cutPanelHint: "อ่านอย่างเดียว — ยังไม่มีอะไรถูกบันทึกหรือถูกโอนจนกว่าจะกดสร้างไฟล์",
    refresh: "รีเฟรช",
    dateFrom: "งานที่ปิดบัญชีตั้งแต่",
    dateTo: "ถึงวันที่",
    dateHint:
      "กรองด้วย “วันที่ปิดบัญชีงาน” (เวลาไทย) — ฐานเดียวกับคิวจ่ายเงิน รปภ เพื่อให้สองขาของงานเดียวกันเคลื่อนพร้อมกัน",
    applyFilter: "ใช้ตัวกรอง",
    clearFilter: "ล้างตัวกรอง",
    jobs: "จำนวนงาน",
    totalCut: "ยอดที่จะกวาดเข้าบัญชี",
    totalCutCaption: "ผลรวม 5 ก้อนด้านล่าง หัก ยอดที่เก็บเงินไม่ได้",
    inWindow: "ในช่วงที่เลือก",
    breakdown: "แยกตามที่มาของยอด",
    component: "ที่มาของยอด",
    amount: "จำนวนเงิน",

    billedCut: "รวมยอดตามบิล",
    billedCutNote: "ผลรวมของ 5 ก้อนด้านบน — คือสิ่งที่บิลที่ปิดแล้ว “ควรจะ” ได้ ก่อนถามว่าลูกค้าโอนมาครบหรือยัง",
    uncollected: "หัก: ตั้งบิลแล้วแต่ยังเก็บเงินไม่ได้",
    uncollectedNote:
      "ยอดปิดงานสูงกว่าที่ลูกค้าจ่ายไว้ล่วงหน้า และระบบยังไม่ได้เรียกเก็บส่วนต่างนั้น — เงินก้อนนี้ยังไม่เข้าบัญชี จึงตัดออกจากไฟล์",
    uncollectedBadge: "ไม่กวาด",
    netToSweep: "= ยอดที่ไฟล์นี้จะโอนจริง",
    netToSweepNote: "ตัวเลขที่ต้องตรงกับยอดเงินเข้าบัญชีรายได้เมื่อธนาคารทำรายการเสร็จ",
    uncollectedCallout:
      "ช่วงนี้มี “ยอดที่ตั้งบิลแล้วแต่ยังเก็บเงินไม่ได้” อยู่ — เกิดตอนปิดงานแล้วยอดจริงสูงกว่าที่ลูกค้าจ่ายล่วงหน้า (เช่น มีทิปเพิ่มทีหลัง) แล้วระบบไม่ได้เรียกเก็บส่วนต่าง · ระบบจงใจไม่กวาดยอดนี้ เพราะเงินไม่ได้อยู่ในบัญชีจริง และบัญชีที่ตัดออกเป็นบัญชีเดียวกับที่เก็บ VAT ของกรมสรรพากรและค่าแรงที่ยังค้างจ่าย รปภ. — กวาดไปจะเป็นการดึงเงินที่ไม่ใช่ของบริษัทออกไป · ยอดนี้ยังเป็นรายได้ตามบัญชี ต้องตามเก็บกับลูกค้าเอง ไม่ได้หายไป",
    uncollectedShort: "เก็บไม่ได้",
    componentLabels: {
      commission: "ค่าคอมมิชชัน",
      cancellation_fee: "ค่ายกเลิกที่เก็บไว้",
      tip: "ทิป",
      unpaid_guard_share: "ส่วนของ รปภ. ที่ยังไม่ได้จ่าย",
      rounding_adjustment: "ส่วนต่างจากการปัดเศษ",
    },
    componentNotes: {
      commission: "ส่วนที่หักจากค่าแรงของ รปภ. — รายได้จริงของแพลตฟอร์ม",
      cancellation_fee: "ค่ายกเลิกที่เก็บไว้เมื่อลูกค้ายกเลิกงาน (ส่วนที่ไม่รวม VAT)",
      tip: "บั๊กที่ยังไม่แก้: ระบบเก็บทิปจากลูกค้าแต่ไม่ได้จ่ายต่อให้ รปภ. — วันที่แก้บั๊กนี้ ยอดตรงนี้จะหายไป",
      unpaid_guard_share:
        "บั๊กที่ยังไม่แก้: งานที่คิดเงินลูกค้าเป็น N คน แต่จ่ายจริงแค่คนเดียว — ส่วนที่เหลือตกอยู่กับแพลตฟอร์ม",
      rounding_adjustment:
        "เศษสตางค์จากการเฉลี่ยชั่วโมงแบบไม่ปัดเทียบกับการจ่ายตามชั่วโมงที่ปัดทศนิยม 2 ตำแหน่ง — ก้อนเดียวที่ติดลบได้ (แพลตฟอร์มขาดทุนเล็กน้อยได้จริง)",
    },
    componentShort: {
      commission: "คอมมิชชัน",
      cancellation_fee: "ค่ายกเลิก",
      tip: "ทิป",
      unpaid_guard_share: "ส่วน รปภ. ค้าง",
      rounding_adjustment: "เศษปัด",
    },
    deferredBugBadge: "บั๊กที่ยังไม่แก้",
    nothingToSweep: "ไม่มีรายการที่ต้องหักเข้าระบบในช่วงนี้",

    notSweptTitle: "เงินในบัญชีเดียวกันที่ “ไม่” อยู่ในไฟล์นี้",
    notSweptIntro:
      "สองก้อนนี้อยู่ในบัญชีรับเงินลูกค้าเหมือนกัน แต่ไม่ใช่ของบริษัท — แสดงไว้ให้เห็น เพื่อจะได้ไม่มีใครมา “รวบ” เข้าไฟล์กวาดยอดในภายหลัง",
    vatNotSwept: "VAT ที่เก็บจากลูกค้า",
    vatNotSweptNote: "เงินของกรมสรรพากร นำส่งด้วยการยื่น ภ.พ.30 — ดูรายงานด้านล่าง",
    guardIncomeNotSwept: "ค่าแรงที่ยังค้างจ่าย รปภ.",
    guardIncomeNotSweptNote: "ออกทางไฟล์จ่ายเงิน รปภ (พร้อมเพย์) ไม่ใช่ไฟล์นี้",

    excludedTitle: "งานที่คำนวณยอดหักไม่ได้",
    excludedIntro:
      "งานเหล่านี้ไม่ถูกนับในยอดรวม และไม่ถูกทำเครื่องหมายว่ากวาดแล้ว จึงจะโผล่มาใหม่ในรอบถัดไป — ตัวเลขข้างบนจึงต่ำกว่าความจริงเท่ากับงานกลุ่มนี้ ไม่ได้หายไปไหน",
    excludedTruncated: (shown, total) =>
      `แสดง ${shown} จากทั้งหมด ${total} งาน (ตัดให้สั้นเพื่อไม่ให้หน้าค้าง) — ยอดรวมด้านบนไม่ได้นับงานกลุ่มนี้อยู่แล้ว`,
    excludedCodeLabels: {
      NOT_SETTLED: "ยังไม่ปิดบัญชี",
      NO_VAT_SPLIT: "ไม่มีการแยก VAT",
      NO_PRICING_SNAPSHOT: "ไม่มีสแนปช็อตราคา",
      DOES_NOT_RECONCILE: "ตัวเลขไม่ตรงกัน",
    },
    reason: "เหตุผล",
    booking: "งาน",
    payment: "รายการชำระ",

    ledgerTitle: "รายการรายงาน (แยกรายงาน)",
    ledgerIntro:
      "ยอดหักของแต่ละงาน แยกให้เห็นทีละก้อน — ไฟล์ OAT มีบรรทัดโอนเดียว รายการเหล่านี้คือที่มาของบรรทัดนั้น",
    ledgerTruncated: (shown, total) =>
      `แสดง ${shown} จาก ${total} งาน (ตัดให้สั้น) — ยอดรวมด้านบนนับครบทุกงานในช่วงที่เลือก`,
    settledOn: "วันที่ปิดบัญชี",
    listSummary: (from, to, total) => `แสดง ${from}–${to} จาก ${total} รายการ`,

    exportPanel: "สร้างไฟล์กวาดยอดเข้าบัญชีบริษัท (OAT)",
    exportPanelHint: "โอนระหว่างบัญชีบริษัทเอง — ไม่ใช่การจ่ายเงินให้ใคร",
    exportHint:
      "ไฟล์นี้กวาด “ทั้งช่วงที่เลือก” ไม่มีการติ๊กเลือกรายงาน เพราะปลายทางมีบัญชีเดียว ไม่มีใครให้เลือก และถ้ากวาดครึ่งเดียวจะเหลือยอดค้างที่ไม่มีใครอธิบายได้ภายหลัง · กดแล้วจะดาวน์โหลดไฟล์ .txt และบันทึกว่างานในช่วงนี้ถูกกวาดแล้ว (กันกวาดซ้ำ) · ถ้าอยากกวาดน้อยลง ให้แคบช่วงวันที่",
    exportBtn: "สร้างไฟล์กวาดยอด SCB",
    exporting: "กำลังสร้างไฟล์…",
    exportError: "สร้างไฟล์ไม่สำเร็จ",
    loadError: "โหลดข้อมูลไม่สำเร็จ",
    loadErrorWindowHint:
      "ถ้าช่วงวันที่กว้างเกินไป ระบบจะ “ปฏิเสธ” แทนการตัดรายการทิ้ง เพราะยอดเงินที่ขาดไปจะดูเหมือนยอดที่ถูกต้อง — ให้แบ่งช่วงวันที่ให้สั้นลงแล้วทำทีละช่วง (หน้าพรีวิวกับการสร้างไฟล์ใช้เกณฑ์เดียวกัน จึงไม่มีทางกวาดคนละชุดกับที่เห็น)",
    netNotPositive:
      "ช่วงนี้มีงานอยู่ แต่ยอดหักรวมกันแล้วไม่เหลือเป็นบวก (ยอดที่เก็บเงินไม่ได้ หรือเศษปัดลบ หักกลบไปหมด) — ธนาคารรับบรรทัดโอนต่ำกว่า ฿0.01 ไม่ได้ จึงสร้างไฟล์ไม่ได้ · ทางแก้ตรงข้ามกับกรณีช่วงกว้างเกิน: ให้ “ขยาย” ช่วงวันที่ หรือรอให้มีงานปิดยอดเพิ่มแล้วค่อยกวาดรวมทีเดียว",

    history: "ประวัติไฟล์กวาดยอด",
    historyHint:
      "ไฟล์กวาดยอดที่สร้างไปแล้วทั้งหมด (ใหม่สุดอยู่บน) — ดาวน์โหลดซ้ำได้ถ้าไฟล์เดิมหาย และบันทึกได้ว่าธนาคารรับหรือปฏิเสธ",
    historyEmpty: "ยังไม่เคยสร้างไฟล์กวาดยอด",
    historyError: "โหลดประวัติไฟล์ไม่สำเร็จ",
    fileRef: "รหัสไฟล์ (SCB)",
    valueDate: "วันที่เงินเข้า",
    jobCount: "จำนวนงาน",
    creditedTo: "เข้าบัญชี",
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
      "ขั้นนี้ย้อนกลับไม่ได้ กดเมื่อเห็นเงินเข้าบัญชีรายได้บริษัทจริงแล้วเท่านั้น — หลังกดจะ “ยกเลิกทั้งไฟล์” ไม่ได้อีก และ “ดึงงานรายตัวกลับ” ก็ไม่ได้เช่นกัน เพราะไฟล์นี้มีบรรทัดโอนเดียวสำหรับทั้งไฟล์ เงินทั้งก้อนจึงเข้าบัญชีรายได้ไปแล้ว การดึงงานกลับจะทำให้รอบหน้ากวาดซ้ำ · งานทุกงานในไฟล์นี้จะถูกนับว่ากวาดแล้วถาวร ถ้าพบทีหลังว่ามีงานไม่ควรถูกกวาด ต้องทำรายการปรับปรุงทางบัญชีแทน (ต่างจากไฟล์จ่าย รปภ และไฟล์คืนเงิน ที่ยังดึงรายตัวกลับได้ เพราะมีบรรทัดโอนแยกต่อคน)",
    noteLabel: "หมายเหตุ (ไม่บังคับ)",
    noteHint: "เช่น ข้อความที่ธนาคารตอบกลับมา — ไม่เกิน 500 ตัวอักษร",
    voidBtn: "ยกเลิกไฟล์",
    voidTitle: "ยกเลิกไฟล์กวาดยอดนี้?",
    voidWarning: (jobs, amount) =>
      `งานทั้งหมดในไฟล์นี้ (${jobs} งาน · ฿${amount}) จะกลับเข้าคิวรอกวาด และกวาดใหม่ได้ในไฟล์รอบถัดไป — ยกเลิกได้เฉพาะไฟล์ที่ยังไม่ได้โอนจริง หรือธนาคารปฏิเสธเท่านั้น ถ้าเงินเข้าบัญชีรายได้ไปแล้วห้ามยกเลิก เพราะรอบหน้าจะกวาดซ้ำ`,
    voidReason: "เหตุผลในการยกเลิก",
    voidReasonHint:
      "ต้องกรอก — อีกหกเดือนจะได้รู้ว่ายกเลิกเพราะอะไร ไม่ใช่กดพลาด (ไม่เกิน 500 ตัวอักษร)",
    voidReasonPlaceholder: "เช่น ธนาคารปฏิเสธไฟล์ / สร้างไฟล์ผิดรอบ / ตั้งบัญชีปลายทางผิด",
    voidConfirm: "ยืนยันยกเลิกไฟล์",
    keepFile: "เก็บไฟล์นี้ไว้",
    voidedReasonPrefix: "เหตุผล",
    cancel: "ยกเลิก",
    actionError: "ทำรายการไม่สำเร็จ",

    detail: {
      viewItems: "ดูรายการในไฟล์",
      title: "งานที่ถูกกวาดด้วยไฟล์นี้",
      subtitle: (fileRef) => `รหัสไฟล์ ${fileRef}`,
      loading: "กำลังโหลดรายการ…",
      error: "โหลดรายการในไฟล์ไม่สำเร็จ",
      empty: "ไฟล์นี้ไม่มีรายการ",
      releaseIntro:
        "ใช้เมื่อมีงานที่ “ไม่ควรถูกกวาด” ติดมาในไฟล์ — ไม่ใช่กรณีธนาคารโอนไม่สำเร็จเหมือนอีกสองไฟล์ เพราะไฟล์ OAT มีบรรทัดโอนเดียว ธนาคารรับทั้งไฟล์หรือไม่รับเลย · ทำได้เฉพาะไฟล์ที่ธนาคาร “ยังไม่ยืนยัน” เท่านั้น เพราะเมื่อยืนยันแล้วเงินทั้งก้อนถูกโอนไปแล้ว ดึงงานกลับจะถูกกวาดซ้ำในรอบถัดไป",
      colBooking: "งาน",
      colComponents: "ที่มาของยอด",
      colUncollected: "เก็บไม่ได้",
      colAmount: "ยอดหัก",
      colState: "สถานะ",
      stateSwept: "กวาดแล้ว",
      stateReleased: "ดึงกลับเข้าคิวแล้ว",
      confirmedTitle: "ไฟล์นี้ธนาคารยืนยันแล้ว — ดึงงานรายตัวกลับไม่ได้",
      confirmedNoRelease:
        "ไฟล์กวาดยอดมีบรรทัดโอน “รายการเดียว” สำหรับทั้งไฟล์ พอธนาคารยืนยัน แปลว่าเงินทั้งก้อนเข้าบัญชีรายได้ไปแล้ว ถ้าดึงงานกลับเข้าคิว รอบถัดไปจะกวาดงานนั้นซ้ำ = ย้ายเงินของบริษัทซ้ำสองรอบ · ต่างจากไฟล์จ่าย รปภ และไฟล์คืนเงินลูกค้า ที่แต่ละคนมีบรรทัดโอนของตัวเอง รายการเดียวจึงเด้งกลับได้จริง · ทางแก้ที่ถูกต้องมีสองทาง: ถ้าเงินยังไม่ได้โอนจริง ให้ยกเลิกทั้งไฟล์ (ต้องเปลี่ยนสถานะไฟล์ก่อน) — ถ้าโอนไปแล้ว ต้องทำรายการปรับปรุงทางบัญชี ไม่ใช่แก้ที่หน้านี้ · ด้านล่างยังดูได้ว่าไฟล์นี้กวาดงานอะไรไปบ้าง",
      selectJob: "เลือกงาน",
      selectAll: "เลือกทั้งหมด",
      selectedSummary: (jobs, amount) => `เลือกไว้ ${jobs} งาน · ฿${amount}`,
      nothingSelected: "ติ๊กเลือกงานที่ไม่ควรถูกกวาดอย่างน้อย 1 งาน",
      releaseWarning:
        "งานที่เลือกจะกลับเข้าคิวรอกวาดและจะถูกกวาดอีกครั้งในไฟล์รอบถัดไป ส่วนเงินที่โอนไปแล้วในไฟล์นี้ยังเป็นยอดเต็ม — บัญชีรายได้จะเกินอยู่เท่ากับยอดที่ดึงกลับ ต้องโอนกลับแก้ไขเอง",
      releaseReason: "เหตุผลที่ดึงงานกลับ",
      releaseReasonHint:
        "ต้องกรอก — บันทึกไว้ว่าทำไมยอดที่บัญชีบอกว่ากวาดแล้วถึงกลับมารอกวาดอีก (ไม่เกิน 500 ตัวอักษร)",
      releaseReasonPlaceholder: "เช่น งานนี้กำลังตรวจสอบข้อพิพาทกับลูกค้า ยังไม่ควรรับรู้เป็นรายได้",
      releaseBtn: "ดึงงานกลับเข้าคิว",
      releasing: "กำลังดึงกลับ…",
      releasedFlash: (jobs) => `ดึง ${jobs} งานกลับเข้าคิวแล้ว`,
      releaseError: "ดึงรายการกลับไม่สำเร็จ",
      tooMany: (max) => `ดึงกลับได้ไม่เกิน ${max} งานต่อครั้ง — กรุณาแบ่งเลือกเป็นหลายรอบ`,
      close: "ปิด",
    },

    reports: {
      title: "รายงานภาษี (ใช้ประกอบการยื่นแบบ)",
      hint: "ตัวเลขสองชุดนี้ใช้กรอกแบบยื่นภาษี ไม่ได้สร้างไฟล์โอนเงินใด ๆ",
      notATransfer:
        "ไม่ใช่ไฟล์โอนเงิน — VAT และภาษีหัก ณ ที่จ่ายที่หักไว้เป็นเงินของกรมสรรพากร นำส่งด้วยการยื่นแบบผ่านระบบ e-filing เท่านั้น และจงใจไม่รวมอยู่ในไฟล์กวาดยอดด้านบน",
      month: "เดือนที่ยื่น",
      monthHint:
        "ใช้กับรายงานทั้งสองชุด — ต้องเลือกเอง ไม่มีค่าเริ่มต้น เพราะเดือนที่ตั้งไว้ให้เองคือการยื่นผิดเดือน",
      load: "ดึงรายงาน",
      loading: "กำลังดึงรายงาน…",
      loadError: "ดึงรายงานไม่สำเร็จ",
      csv: "ดาวน์โหลด CSV",
      downloading: "กำลังดาวน์โหลด…",
      downloadError: "ดาวน์โหลด CSV ไม่สำเร็จ",
      notLoaded: "เลือกเดือนแล้วกด “ดึงรายงาน”",
      empty: "ไม่มีรายการในเดือนนี้",
      customer: "ลูกค้า",

      vat: {
        title: "รายงานภาษีขาย (ภ.พ.30)",
        hint: "หนึ่งบรรทัดต่อหนึ่งรายการชำระที่เก็บ VAT พร้อมยอดรวมที่ใช้กรอกลงแบบ ภ.พ.30",
        basis:
          "อ้างอิง “วันที่ลูกค้าจ่ายเงิน” (จุดรับรู้ภาษีของบริการคือวันรับชำระ) ซึ่งเป็นฐานเดียวกับกราฟรายได้ ตัวเลขจึงตรงกัน — ต่างจากไฟล์กวาดยอดที่อ้างอิงวันปิดบัญชีงาน",
        rows: "จำนวนรายการ",
        subtotal: "ยอดก่อน VAT",
        vat: "VAT",
        total: "รวมทั้งสิ้น",
        colDate: "วันที่จ่าย",
        colPayment: "รายการชำระ",
        colBooking: "งาน",
      },

      wht: {
        title: "รายชื่อผู้ถูกหักภาษี ณ ที่จ่าย (ภ.ง.ด.)",
        hint: "รปภ. ทุกคนที่ถูกหักภาษีในเดือนนั้น พร้อมเลขประจำตัวผู้เสียภาษี ยอดเงินได้ และภาษีที่หักไว้",
        basis:
          "อ้างอิง “วันที่เงินเข้า” ของไฟล์จ่ายเงิน (วันที่จ่ายจริงคือเดือนที่ต้องยื่น) · รายการที่ถูกยกเลิกไม่นับ เพราะเงินที่ไม่เคยจ่ายก็ไม่เคยถูกหักภาษี",
        formLabel: "แบบที่ใช้ยื่น",
        formHint:
          "ค่าที่ตั้งไว้ในหน้าตั้งค่าการจ่าย รายงานแสดงตามที่บันทึกไว้เท่านั้น ไม่แก้ให้เอง — แบบไหนที่ต้องใช้เป็นการตัดสินใจทางภาษีของผู้ใช้",
        incomeTypeLabel: "ประเภทเงินได้",
        settingsNote: "แบบ ประเภทเงินได้ และอัตราหัก ตั้งค่าที่หน้าจ่ายเงิน รปภ —",
        payees: "จำนวนผู้ถูกหัก",
        income: "เงินได้รวม",
        wht: "ภาษีที่หักรวม",
        colGuard: "รปภ.",
        colTaxId: "เลขประจำตัวผู้เสียภาษี",
        colAddress: "ที่อยู่",
        colJobs: "จำนวนงาน",
        noTaxId: "ไม่มีข้อมูล",
        noName: "ไม่มีข้อมูลโปรไฟล์",
      },
    },
  },

  en: {
    title: "Platform cut",
    subtitle:
      "What the platform keeps out of settled jobs → swept into the company revenue account by one SCB file (product OAT), alongside the two tax reports that back a filing.",

    oatIntro:
      "This file credits the COMPANY's OWN account (product OAT — own-account transfer). It pays nobody, unlike the guard-payout and customer-refund files, which send money to other people. Do not mix the three up when uploading to SCB.",
    scopeNote:
      "What is swept: the commission deducted from the guard's pay · the retained cancellation fee · the tip · the billed-but-unpaid share of a multi-guard booking · the proration rounding drift — itemised one by one below.",
    taxNote:
      "What is NOT swept, and never will be from here: the 7% VAT and the tax withheld from guards. Both are the Revenue Department's money sitting in the same bank account, and both are remitted by e-filing (ภ.พ.30 monthly, ภ.ง.ด.3/53 by the 7th of the following month) — not by a bulk transfer file.",
    configNote:
      "The debit account, who pays the transfer fee, and the “company revenue account” (this file's destination) all live on the guard-payout screen —",
    configLink: "Open payout settings",
    destination: "Credited to",
    noDestination:
      "No company revenue account is configured yet — the sweep file cannot be generated until one is set, on the payout settings screen.",

    cutPanel: "The cut for the selected window",
    cutPanelHint: "Read-only — nothing is recorded or moved until you generate the file",
    refresh: "Refresh",
    dateFrom: "Jobs settled from",
    dateTo: "to",
    dateHint:
      "Filtered on the day the job was SETTLED (Thai local days) — the same basis the guard-payout backlog uses, so the two halves of one job move together.",
    applyFilter: "Apply filter",
    clearFilter: "Clear filter",
    jobs: "Jobs",
    totalCut: "To sweep",
    totalCutCaption: "the five components below, less what was never collected",
    inWindow: "in the window",
    breakdown: "Where the money comes from",
    component: "Component",
    amount: "Amount",

    billedCut: "Billed cut",
    billedCutNote:
      "The five components above, summed — what the settled bills earned, before asking whether the customer actually transferred it.",
    uncollected: "Less: billed but never collected",
    uncollectedNote:
      "The settled bill came out above what the customer pre-paid and the difference was never charged — that money is not in the bank, so it is left out of the file.",
    uncollectedBadge: "not swept",
    netToSweep: "= What this file transfers",
    netToSweepNote: "The figure that must match the credit landing in the revenue account.",
    uncollectedCallout:
      "This window contains money that was BILLED but never COLLECTED — it happens when a job settles above what the customer pre-paid (a tip added afterwards, say) and the difference is never charged. It is deliberately NOT swept: the baht never arrived, and the account the file debits is the same one holding the Revenue Department's VAT and the guards' unpaid income, so sweeping it would draw down money that is not the company's. It is still earned revenue in the books — it has to be collected from the customer, not written off here.",
    uncollectedShort: "Uncollected",
    componentLabels: {
      commission: "Commission",
      cancellation_fee: "Retained cancellation fee",
      tip: "Tip",
      unpaid_guard_share: "Guard share never paid out",
      rounding_adjustment: "Proration rounding drift",
    },
    componentNotes: {
      commission: "Deducted from the guard's pay — the platform's real revenue.",
      cancellation_fee:
        "Kept when a customer backs out of a booking (the VAT-exclusive part of it).",
      tip: "A KNOWN, DEFERRED bug: the customer is billed a gratuity the guard never receives. The day it is fixed, this figure disappears.",
      unpaid_guard_share:
        "A KNOWN, DEFERRED bug: a booking billed for N guards pays exactly one, and the rest stays with the platform.",
      rounding_adjustment:
        "Satang of drift between prorating on the unrounded worked-hours ratio and paying on hours rounded to 2 dp — the only component that may be NEGATIVE (the platform really can be marginally out of pocket).",
    },
    componentShort: {
      commission: "Commission",
      cancellation_fee: "Cancel fee",
      tip: "Tip",
      unpaid_guard_share: "Unpaid share",
      rounding_adjustment: "Rounding",
    },
    deferredBugBadge: "deferred bug",
    nothingToSweep: "Nothing to sweep in this window",

    notSweptTitle: "Money in the same account that is NOT in this file",
    notSweptIntro:
      "These two sit in the same receiving account and are not the company's. They are shown so nobody later “simplifies” them into the sweep.",
    vatNotSwept: "VAT collected from customers",
    vatNotSweptNote: "The Revenue Department's money, remitted via ภ.พ.30 — see the report below.",
    guardIncomeNotSwept: "Guard income still owed",
    guardIncomeNotSweptNote: "Leaves via the guard-payout (PromptPay) file, not this one.",

    excludedTitle: "Jobs whose cut could not be computed",
    excludedIntro:
      "These are counted nowhere and are NOT marked swept, so they reappear in the next run — the totals above are under-stated by exactly this group, and nothing is lost.",
    excludedTruncated: (shown, total) =>
      `Showing ${shown} of ${total} jobs (the list is capped so the page stays usable) — the totals above never included this group anyway.`,
    excludedCodeLabels: {
      NOT_SETTLED: "Not settled yet",
      NO_VAT_SPLIT: "No VAT split",
      NO_PRICING_SNAPSHOT: "No pricing snapshot",
      DOES_NOT_RECONCILE: "Figures disagree",
    },
    reason: "Reason",
    booking: "Booking",
    payment: "Payment",

    ledgerTitle: "Per-job ledger",
    ledgerIntro:
      "Each job's cut, itemised. An OAT file carries ONE credit line — these rows are what that line is made of.",
    ledgerTruncated: (shown, total) =>
      `Showing ${shown} of ${total} jobs (capped) — the totals above cover every job in the window.`,
    settledOn: "Settled",
    listSummary: (from, to, total) => `Showing ${from}–${to} of ${total}`,

    exportPanel: "Generate the own-account sweep file (OAT)",
    exportPanelHint: "A transfer between the company's own accounts — not a payment to anyone",
    exportHint:
      "This file sweeps the WHOLE selected window; there is deliberately no per-job tick list, because an OAT file credits one destination — there is nobody to choose between, and sweeping half a day's cut would leave the rest looking unswept for a reason nobody could reconstruct later. Generating downloads a .txt and marks these jobs swept (which prevents a double sweep). To sweep less, narrow the date window.",
    exportBtn: "Generate SCB sweep file",
    exporting: "Generating…",
    exportError: "Failed to generate the file",
    loadError: "Failed to load",
    loadErrorWindowHint:
      "If the window is very wide the server REFUSES rather than truncating the list — a money total that is short looks exactly like a correct one — so the remedy is a narrower date window, taken a stretch at a time. The preview and the export are refused on identical terms, so you can never sweep a different set of jobs from the one you read.",
    netNotPositive:
      "There are jobs in this window, but their cut nets to nothing transferable (the uncollected bills and the negative rounding cancelled it out), and a bank credit line cannot be below ฿0.01. The remedy is the opposite of the too-wide one: WIDEN the window, or wait for more jobs to settle and sweep them together.",

    history: "Generated sweep files",
    historyHint:
      "Every sweep file generated so far, newest first — re-download one whose copy was lost, and record whether the bank took it.",
    historyEmpty: "No sweep file has been generated yet",
    historyError: "Failed to load the file history",
    fileRef: "File ref (SCB)",
    valueDate: "Value date",
    jobCount: "Jobs",
    creditedTo: "Credited to",
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
      "This step cannot be undone — only take it once you have seen the money arrive in the company revenue account. Afterwards neither the whole-file void NOR the per-job release is available: this file carries ONE credit line for the whole batch, so confirming means the entire amount moved, and releasing a job would let the next sweep move it a second time. Every job in it stays marked swept, permanently; a job later found not to belong needs an accounting adjustment instead. (The payout and refund files DO keep their per-item release — theirs carry one credit line per recipient.)",
    noteLabel: "Note (optional)",
    noteHint: "e.g. the bank's own message back — 500 characters max",
    voidBtn: "Void file",
    voidTitle: "Void this sweep file?",
    voidWarning: (jobs, amount) =>
      `Every job in this file (${jobs} jobs · ฿${amount}) goes back into the sweepable backlog and can be swept again by the next file. Only void a file the bank never took, or refused. If the money already reached the revenue account, do NOT void it — the next run would sweep the same cut a second time.`,
    voidReason: "Reason for voiding",
    voidReasonHint:
      "Required — six months from now this is what tells a void apart from a mis-click (500 characters max)",
    voidReasonPlaceholder:
      "e.g. bank refused the file / wrong period / destination account was misconfigured",
    voidConfirm: "Void the file",
    keepFile: "Keep the file",
    voidedReasonPrefix: "Reason",
    cancel: "Cancel",
    actionError: "The action failed",

    detail: {
      viewItems: "View items",
      title: "Jobs this file swept",
      subtitle: (fileRef) => `File ref ${fileRef}`,
      loading: "Loading the file's items…",
      error: "Failed to load the items in this file",
      empty: "This file has no rows",
      releaseIntro:
        "For a job that should never have been collected — NOT for a failed transfer, which is the other two files' case. An OAT file has one credit line: the bank takes it or it does not. Only available while the bank has NOT confirmed the file, because once it has, the whole amount has moved and a released job would simply be swept again by the next file.",
      colBooking: "Booking",
      colComponents: "Made up of",
      colUncollected: "Uncollected",
      colAmount: "Cut",
      colState: "State",
      stateSwept: "Swept",
      stateReleased: "Back in the backlog",
      confirmedTitle: "The bank confirmed this file — jobs cannot be released from it",
      confirmedNoRelease:
        "A sweep file carries ONE credit line for the whole batch, so a confirmed file means the entire amount has already moved into the revenue account. Releasing a job would put it back in the backlog and the next sweep would move its cut a SECOND time — real double-movement of company money. (The guard-payout and customer-refund files give every recipient their own credit line, which is why one item there genuinely can bounce and be released.) Two remedies are open: if the money truly never moved, void the whole file — which needs the file's status changed back first; if it did move, this is an accounting adjustment, not a change on this screen. The ledger below stays readable either way.",
      selectJob: "Select job",
      selectAll: "Select all",
      selectedSummary: (jobs, amount) => `${jobs} jobs · ฿${amount} selected`,
      nothingSelected: "Tick at least one job that should not have been swept",
      releaseWarning:
        "The selected jobs go back into the sweepable backlog and will be swept again by the next file, while the money this file already moved stays at its full amount — the revenue account will be over-swept by the released total until you make a correcting transfer.",
      releaseReason: "Why these are going back",
      releaseReasonHint:
        "Required — it is the record of why money the ledger says was collected is queued to be collected again (500 characters max)",
      releaseReasonPlaceholder:
        "e.g. this job is in dispute with the customer and must not be recognised as revenue yet",
      releaseBtn: "Release back to the backlog",
      releasing: "Releasing…",
      releasedFlash: (jobs) => `Released ${jobs} jobs back into the backlog`,
      releaseError: "Failed to release those jobs",
      tooMany: (max) => `At most ${max} jobs can be released at once — do it in several passes`,
      close: "Close",
    },

    reports: {
      title: "Tax reports (they back a FILING)",
      hint: "These two figures are transcribed onto a tax return. They generate no transfer file.",
      notATransfer:
        "Not a bank transfer — the VAT and the withheld tax are the Revenue Department's money, remitted only by e-filing, and are deliberately excluded from the sweep file above.",
      month: "Filing period",
      monthHint:
        "Applies to both reports — you have to pick it: a defaulted period on a tax report is a filing for the wrong month.",
      load: "Load reports",
      loading: "Loading…",
      loadError: "Failed to load the report",
      csv: "Download CSV",
      downloading: "Downloading…",
      downloadError: "Failed to download the CSV",
      notLoaded: "Pick a month, then press “Load reports”",
      empty: "Nothing in this period",
      customer: "Customer",

      vat: {
        title: "Output-VAT register (ภ.พ.30)",
        hint: "One line per settled payment that charged VAT, plus the period totals an accountant transcribes onto the ภ.พ.30.",
        basis:
          "Bucketed on the day the customer PAID (Thai VAT on a service has its tax point at receipt of payment) — the same basis the revenue chart uses, so the two tie out. The sweep file above buckets on the settle day instead.",
        rows: "Rows",
        subtotal: "Subtotal (ex VAT)",
        vat: "VAT",
        total: "Total",
        colDate: "Paid",
        colPayment: "Payment",
        colBooking: "Booking",
      },

      wht: {
        title: "ภ.ง.ด. payee list",
        hint: "Every guard who had tax withheld in the period, with their TIN, the gross income paid and the tax withheld.",
        basis:
          "Bucketed on the payout file's VALUE DATE — the day the transfer settles is the day the payee was paid, which is the month the filing covers. Voided items are excluded: money that was never paid was never withheld.",
        formLabel: "Form",
        formHint:
          "From the stored payout settings, reported exactly as saved and never corrected here — which form applies is the operator's tax decision.",
        incomeTypeLabel: "Income type",
        settingsNote:
          "The form, income type and withholding rate are set on the guard-payout screen —",
        payees: "Payees",
        income: "Gross income",
        wht: "Tax withheld",
        colGuard: "Guard",
        colTaxId: "Tax ID",
        colAddress: "Address",
        colJobs: "Jobs",
        noTaxId: "not on file",
        noName: "no profile on file",
      },
    },
  },
};
