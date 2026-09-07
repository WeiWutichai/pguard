"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { AlertTriangle, Download, FileText, Loader2 } from "lucide-react";

import type { components } from "@/api/generated/payment";
import {
  Badge,
  Button,
  Field,
  Input,
  KpiCard,
  KpiGrid,
  Panel,
  PanelBody,
  PanelHead,
  Pagination,
  Table,
  Td,
  Th,
  Tr,
} from "@/components/ui";
import { paymentApi } from "@/lib/api";
import { useLanguage } from "@/lib/i18n";
import type { Lang } from "@/lib/lang";
import { useNameResolver } from "@/lib/use-names";

import { COPY as PAYOUT_COPY, WHT_FORM_CODES, type WhtFormCode } from "../payouts/copy";
import { fmtDay } from "../payouts/dates";
import { saveBlob } from "../payouts/download-file";
// `ReportKind` — which of the two reports an action is about — is IMPORTED, not restated here: the
// same union is the CSV filename's stem, and a local copy could drift from the name a file is saved
// under.
import {
  fallbackReportName,
  parseContentDispositionFilename,
  type ReportKind,
} from "../payouts/download-name";
import { COPY, LEDGER_PAGE_SIZE } from "./copy";

type VatRegisterReport = components["schemas"]["VatRegisterReport"];
type WhtPayeeReport = components["schemas"]["WhtPayeeReport"];

/**
 * Unwrap the `data` of a report response.
 *
 * Both endpoints declare TWO 200 content types (`application/json` and `text/csv`), so codegen types
 * the JSON read's body as `envelope | string` and the envelope's own `data` as optional. This is the
 * one narrowing that fact needs: an object body hands back its `data`, anything else (the CSV shape,
 * an empty body) hands back `null` — which the sections below render as FAILED, never as zeros. A
 * tax figure that silently reads ฿0.00 is the worst failure mode on this screen: it is a number an
 * accountant would transcribe onto a return.
 */
function reportData<T>(payload: unknown): T | null {
  if (!payload || typeof payload !== "object") return null;
  const data = (payload as { data?: unknown }).data;
  return data === undefined || data === null ? null : (data as T);
}

/** The typed message a 400 carries (e.g. an unparseable month), when present. */
const apiMessage = (err: unknown): string | null => {
  const message = (err as { error?: { message?: unknown } } | undefined)?.error?.message;
  return typeof message === "string" && message.trim() ? message : null;
};

/** The name the SERVER chose for a report CSV, falling back to `<kind>-<month>.csv` — the same
 *  shape, so a stripped `Content-Disposition` (an off-origin deployment, a proxy) still saves a
 *  file whose name names its filing period. */
const csvNameFrom = (res: { response?: Response }, kind: ReportKind, month: string): string =>
  parseContentDispositionFilename(res.response?.headers.get("content-disposition"), "csv") ??
  fallbackReportName(kind, month);

/** Today's month as `YYYY-MM` — the picker's starting value, never a report's period. Nothing is
 *  fetched until the admin presses Load, so this is a convenience, not a default filing month (the
 *  contract is explicit that a defaulted period is a filing for the wrong one). */
function currentMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

/** The CSV button, identical on both reports — one copy so the two can never disagree about when it
 *  is disabled or what it says while a download is in flight. */
function CsvButton({
  label,
  busyLabel,
  busy,
  disabled,
  onClick,
}: {
  label: string;
  busyLabel: string;
  busy: boolean;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <Button variant="secondary" className="ml-auto" onClick={onClick} disabled={disabled}>
      {busy ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}
      {busy ? busyLabel : label}
    </Button>
  );
}

/**
 * The ภ.พ.30 output-VAT register for one loaded month.
 *
 * Mounted with `key={month}` by the parent, so a new period starts on page 1 without this component
 * resetting its own state inside an effect. Client-paged: the endpoint returns the whole month in
 * one body (the CSV is the bulk artefact), and a month of payments does not belong on screen at
 * once.
 */
function VatSection({ report, month, lang }: { report: VatRegisterReport; month: string; lang: Lang }) {
  const c = COPY[lang].reports;
  const listSummary = COPY[lang].listSummary;
  const [page, setPage] = useState(1);

  const rows = report.rows;
  const pageCount = Math.max(1, Math.ceil(rows.length / LEDGER_PAGE_SIZE));
  const slice = useMemo(
    () => rows.slice((page - 1) * LEDGER_PAGE_SIZE, page * LEDGER_PAGE_SIZE),
    [rows, page],
  );
  // Names for the VISIBLE page only. The report deliberately carries customer ids rather than names
  // (resolving them server-side would be a cross-service fan-out per row on a report that runs to
  // thousands of rows a month); the admin panel's batch resolver is the intended way back, and
  // asking it for one page at a time is what keeps that true.
  const visibleIds = useMemo(() => slice.map((r) => r.customer_id), [slice]);
  const { resolve } = useNameResolver(visibleIds, lang);

  return (
    <>
      {/* No `?? "0.00"` on any of these. Every figure here is `required` in the contract, so a
          missing one is a build error — and a tax total that renders a confident ฿0.00 is the worst
          failure this screen has: it is a number an accountant transcribes onto a ภ.พ.30. */}
      <KpiGrid className="mb-4">
        <KpiCard label={c.vat.rows} value={String(report.row_count)} caption={month} />
        <KpiCard label={c.vat.subtotal} value={`฿${report.total_subtotal}`} />
        <KpiCard label={c.vat.vat} value={`฿${report.total_vat}`} />
        <KpiCard label={c.vat.total} value={`฿${report.total_amount}`} />
      </KpiGrid>

      {rows.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted">{c.empty}</p>
      ) : (
        <>
          <Table>
            <thead>
              <Tr>
                <Th>{c.vat.colDate}</Th>
                <Th>{c.customer}</Th>
                <Th>{c.vat.colBooking}</Th>
                <Th className="text-right">{c.vat.subtotal}</Th>
                <Th className="text-right">{c.vat.vat}</Th>
                <Th className="text-right">{c.vat.total}</Th>
              </Tr>
            </thead>
            <tbody>
              {slice.map((row) => {
                // The RESOLVER may still have nothing — a name is looked up across services and can
                // legitimately be missing. That fallback stays; the money ones are gone.
                const who = resolve(row.customer_id);
                return (
                  <Tr key={row.payment_id}>
                    <Td className="whitespace-nowrap tabular-nums">{fmtDay(row.date, lang)}</Td>
                    <Td title={who?.title}>{who?.label ?? "—"}</Td>
                    {/* No link: `/bookings` takes no id parameter, so one would land on an
                        unfiltered list and look like a way in while being none. */}
                    <Td className="font-mono text-xs" title={row.booking_id}>
                      {row.booking_id.slice(0, 8)}
                    </Td>
                    <Td className="text-right tabular-nums">฿{row.subtotal}</Td>
                    <Td className="text-right tabular-nums">฿{row.vat}</Td>
                    <Td className="text-right font-semibold tabular-nums">฿{row.total}</Td>
                  </Tr>
                );
              })}
            </tbody>
          </Table>
          <Pagination
            page={page}
            pageCount={pageCount}
            onPage={setPage}
            summary={listSummary(
              (page - 1) * LEDGER_PAGE_SIZE + 1,
              Math.min(page * LEDGER_PAGE_SIZE, rows.length),
              rows.length,
            )}
          />
        </>
      )}
    </>
  );
}

/**
 * The ภ.ง.ด.3/53 payee list for one loaded month.
 *
 * Not paged: this is one row per PAYEE per month, which is the guard roster, not the payment volume.
 * The form code and income type are shown because the filing is made against them — and shown
 * exactly as stored, never corrected here (which form applies is the operator's tax decision).
 */
function WhtSection({ report, month, lang }: { report: WhtPayeeReport; month: string; lang: Lang }) {
  const c = COPY[lang].reports;
  const payoutCopy = PAYOUT_COPY[lang];
  const rows = report.rows;

  /** The stored ภ.ง.ด. code, rendered with the payout screen's own label so the two screens can
   *  never name the same form differently. A code outside SCB's list (a legacy or hand-edited row)
   *  is shown RAW rather than snapped to a default — which form applies is a TAX decision, and a
   *  report that quietly corrected it would state something other than what was certified. */
  const code = report.form_type_code;
  const formLabel = (WHT_FORM_CODES as readonly string[]).includes(code)
    ? payoutCopy.whtFormLabels[code as WhtFormCode]
    : code;

  return (
    <>
      <div className="mb-4 flex flex-wrap items-center gap-x-5 gap-y-2 rounded-lg border border-border bg-sunken px-3.5 py-3 text-[12.5px] text-muted">
        <span className="flex items-center gap-2">
          {c.wht.formLabel}: <Badge tone="blue">{formLabel}</Badge>
        </span>
        <span>
          {c.wht.incomeTypeLabel}: {report.income_type_code}
          {report.income_description ? ` · ${report.income_description}` : ""}
        </span>
        <span className="basis-full text-faint">{c.wht.formHint}</span>
      </div>

      {/* Same rule as the VAT register: no money fallbacks. `฿0.00 withheld` beside a populated
          payee list is a figure that would be filed. */}
      <KpiGrid className="mb-4">
        <KpiCard label={c.wht.payees} value={String(report.payee_count)} caption={month} />
        <KpiCard label={c.wht.income} value={`฿${report.total_income}`} />
        <KpiCard label={c.wht.wht} value={`฿${report.total_wht}`} />
      </KpiGrid>

      {rows.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted">{c.empty}</p>
      ) : (
        <Table>
          <thead>
            <Tr>
              <Th>{c.wht.colGuard}</Th>
              <Th>{c.wht.colTaxId}</Th>
              <Th className="text-right">{c.wht.colJobs}</Th>
              <Th className="text-right">{c.wht.income}</Th>
              <Th className="text-right">{c.wht.wht}</Th>
            </Tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <Tr key={row.guard_id}>
                {/* Name and address come from the REPORT (profile resolved them server-side), not
                    from the batch resolver — a payee whose profile is missing is STILL listed,
                    because the withholding happened and the filing has to account for it. */}
                <Td title={row.address ?? row.guard_id}>
                  {row.name ?? <span className="text-faint">{c.wht.noName}</span>}
                </Td>
                <Td className="font-mono text-xs">
                  {row.tax_id ?? <span className="text-faint">{c.wht.noTaxId}</span>}
                </Td>
                <Td className="text-right tabular-nums">{row.job_count}</Td>
                <Td className="text-right tabular-nums">฿{row.income}</Td>
                <Td className="text-right font-semibold tabular-nums">฿{row.wht}</Td>
              </Tr>
            ))}
          </tbody>
        </Table>
      )}
    </>
  );
}

/**
 * JOB 3 of the platform-cut screen — the two TAX REPORTS.
 *
 * These are the other half of *ยอดที่โดนหักเข้าระบบ*, and the half that must never end up in the
 * sweep file. The VAT we charge customers and the tax we withhold from guards sit in the SAME bank
 * account as the platform's own cut, and both are the Revenue Department's money: VAT is a liability
 * from the moment we take it, the withheld WHT is the guard's tax we hold on the department's
 * behalf. Both are remitted by e-filing — ภ.พ.30 monthly, ภ.ง.ด.3/53 by the 7th of the following
 * month — so they get a REPORT that backs a filing, and never a transfer file.
 *
 * That is why this section is visually a sibling of the sweep panel and not a tab on it, why the
 * callout says "not a bank transfer" in the admin's own language, and why each report names the
 * timestamp it buckets on: the VAT register buckets on the day the customer PAID and the payee list
 * on the payout file's VALUE DATE, neither of which is the settle day the sweep uses. Three streams
 * out of one account can only be tied out because each says which basis it used.
 *
 * ONE month picker for both, deliberately: the two filings cover the same calendar month, and two
 * pickers would let an admin pull ภ.พ.30 for August next to ภ.ง.ด. for September and read the pair
 * as a reconciliation.
 */
export function TaxReports() {
  const { lang } = useLanguage();
  const copy = COPY[lang];
  const c = copy.reports;

  /** The month in the picker. */
  const [month, setMonth] = useState(currentMonth);
  /** The month the LOADED reports actually cover — what a CSV download must be run with, so a saved
   *  file can never carry a period the numbers on screen do not. */
  const [loadedMonth, setLoadedMonth] = useState<string | null>(null);
  const [vat, setVat] = useState<VatRegisterReport | null>(null);
  const [wht, setWht] = useState<WhtPayeeReport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  /** Which CSV is being fetched (`null` = none) — one button's spinner, not the section's. */
  const [downloading, setDownloading] = useState<ReportKind | null>(null);
  const [downloadError, setDownloadError] = useState<string | null>(null);

  const monthValid = /^\d{4}-\d{2}$/u.test(month);

  const load = async () => {
    if (!monthValid) return;
    setLoading(true);
    setError(null);
    setDownloadError(null);
    // Both at once: they are one month-end task, and a section whose numbers are a month older than
    // the one beside it is worse than one that is briefly empty.
    const [vatRes, whtRes] = await Promise.all([
      paymentApi.GET("/admin/reports/vat-register", { params: { query: { month } } }),
      paymentApi.GET("/admin/reports/wht-payees", { params: { query: { month } } }),
    ]);
    setLoading(false);
    const vatData = vatRes.error ? null : reportData<VatRegisterReport>(vatRes.data);
    const whtData = whtRes.error ? null : reportData<WhtPayeeReport>(whtRes.data);
    if (vatData === null || whtData === null) {
      setError(apiMessage(vatRes.error) ?? apiMessage(whtRes.error) ?? c.loadError);
    }
    setVat(vatData);
    setWht(whtData);
    // Only claim a period once something actually came back for it — otherwise the screen keeps
    // asking for a month rather than showing two empty reports under one.
    setLoadedMonth(vatData !== null || whtData !== null ? month : null);
  };

  /**
   * Download one report as the spreadsheet an accountant works in.
   *
   * Read as a BLOB, never as text. The server prepends a UTF-8 BOM on purpose — without it Excel on
   * Thai Windows renders every Thai name in the file as mojibake — and `Response.text()` performs a
   * UTF-8 decode, which by specification strips a leading BOM. Going through a string here would
   * silently undo the server's fix; this way the bytes reach disk exactly as they arrived.
   *
   * Run against `loadedMonth`, not the picker: the button sits under the numbers it belongs to, and
   * a CSV for a month the admin had merely typed but not loaded would disagree with them.
   */
  const downloadCsv = async (kind: ReportKind) => {
    const period = loadedMonth;
    if (!period) return;
    setDownloading(kind);
    setDownloadError(null);
    const res =
      kind === "vat-register"
        ? await paymentApi.GET("/admin/reports/vat-register", {
            params: { query: { month: period, format: "csv" } },
            parseAs: "blob",
          })
        : await paymentApi.GET("/admin/reports/wht-payees", {
            params: { query: { month: period, format: "csv" } },
            parseAs: "blob",
          });
    setDownloading(null);
    if (res.error || !(res.data instanceof Blob)) {
      setDownloadError(apiMessage(res.error) ?? c.downloadError);
      return;
    }
    saveBlob(res.data, csvNameFrom(res, kind, period));
  };

  return (
    <Panel>
      <PanelHead title={c.title} sub={c.hint} />
      <PanelBody>
        {/* The sentence that has to stop these being read as a third bank file. */}
        <p className="mb-5 flex items-start gap-2 rounded-lg border border-info/35 bg-info-bg px-3.5 py-3 text-[12.5px] text-info">
          <FileText className="mt-0.5 size-4 shrink-0" />
          <span>{c.notATransfer}</span>
        </p>

        <div className="mb-2 flex flex-wrap items-end gap-3">
          <Field label={c.month} className="mb-0">
            <Input
              type="month"
              value={month}
              error={!monthValid}
              onChange={(e) => setMonth(e.target.value)}
              className="w-52"
            />
          </Field>
          <Button onClick={() => void load()} disabled={loading || !monthValid}>
            {loading ? <Loader2 className="size-4 animate-spin" /> : null}
            {loading ? c.loading : c.load}
          </Button>
        </div>
        <p className="mb-5 text-xs text-faint">{c.monthHint}</p>

        {error && (
          <p
            role="alert"
            className="mb-4 flex items-center gap-2 rounded-lg border border-danger/40 bg-danger-bg px-4 py-3 text-sm text-danger"
          >
            <AlertTriangle className="size-4 shrink-0" /> {error}
          </p>
        )}
        {downloadError && (
          <p role="alert" className="mb-4 text-sm text-danger">
            {downloadError}
          </p>
        )}

        {loadedMonth === null ? (
          <p className="py-8 text-center text-sm text-muted">{c.notLoaded}</p>
        ) : (
          <div className="space-y-8">
            {/* ── ภ.พ.30 — the output-VAT register ───────────────────── */}
            <section>
              <div className="mb-2 flex flex-wrap items-start gap-3">
                <div className="min-w-0">
                  <h4 className="text-sm font-semibold text-text-strong">{c.vat.title}</h4>
                  <p className="text-[12.5px] text-muted">{c.vat.hint}</p>
                </div>
                <CsvButton
                  label={c.csv}
                  busyLabel={c.downloading}
                  busy={downloading === "vat-register"}
                  disabled={vat === null || downloading !== null}
                  onClick={() => void downloadCsv("vat-register")}
                />
              </div>
              <p className="mb-4 text-xs text-faint">{c.vat.basis}</p>

              {/* A failed report renders as FAILED, never as zeros — the two are fetched together
                  but fail independently, and "฿0.00 VAT this month" beside a working payee list is
                  a figure someone would put on a return. */}
              {vat === null ? (
                <p role="alert" className="py-6 text-center text-sm text-danger">
                  {c.loadError}
                </p>
              ) : (
                // Keyed by period: a new month starts on page 1 without an effect resetting it.
                <VatSection key={loadedMonth} report={vat} month={loadedMonth} lang={lang} />
              )}
            </section>

            {/* ── ภ.ง.ด.3/53 — the payee list ────────────────────────── */}
            <section>
              <div className="mb-2 flex flex-wrap items-start gap-3">
                <div className="min-w-0">
                  <h4 className="text-sm font-semibold text-text-strong">{c.wht.title}</h4>
                  <p className="text-[12.5px] text-muted">{c.wht.hint}</p>
                </div>
                <CsvButton
                  label={c.csv}
                  busyLabel={c.downloading}
                  busy={downloading === "wht-payees"}
                  disabled={wht === null || downloading !== null}
                  onClick={() => void downloadCsv("wht-payees")}
                />
              </div>
              <p className="mb-3 text-xs text-faint">{c.wht.basis}</p>

              {wht === null ? (
                <p role="alert" className="py-6 text-center text-sm text-danger">
                  {c.loadError}
                </p>
              ) : (
                <WhtSection report={wht} month={loadedMonth} lang={lang} />
              )}

              <p className="mt-3 text-xs text-faint">
                {c.wht.settingsNote}{" "}
                <Link href="/payouts" className="font-medium text-brand-int hover:underline">
                  {copy.configLink}
                </Link>
              </p>
            </section>
          </div>
        )}
      </PanelBody>
    </Panel>
  );
}
