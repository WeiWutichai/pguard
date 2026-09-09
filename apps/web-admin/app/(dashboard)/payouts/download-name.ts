/**
 * Naming the downloaded SCB file after the BANK's own reference instead of the local clock.
 *
 * The export response carries `Content-Disposition: attachment; filename="…"`, and the server
 * derives that name from `scb_export::download_filename(&batch.file_ref)` =
 * `SCB_file_reference_<first 12 chars of the file ref>.txt`
 * (`docs/reviews/CPX_Toolkit_Reverse_Engineering.md:58`, `generateCustomerFileReferanceName`).
 * `file_ref` is the bank's identity for the batch and is also the `file_ref` column of the batch row
 * (`payment.payout_batches` for guard payouts, `payment.refund_batches` for customer refunds,
 * `payment.deduction_batches` for the platform-cut sweep), so keeping that name is what ties a file
 * sitting in the admin's Downloads folder back to the row that marked those obligations settled.
 *
 * A locally generated date stamp cannot do that: two runs on the same day both land as
 * `SCB_<stream>_<date>.txt`, the browser disambiguates them with "(1)", and nothing on disk says
 * which batch is which. The batch history and its re-download are the way back when that link is
 * lost — this name is what an operator matches the two against.
 *
 * ALL THREE money streams import this module: one parser, one fallback shape. The streams differ
 * only in the fallback's stem (see [FileStream]) — the header path is identical, because the server
 * derives the same `SCB_file_reference_…` name from any of the three batches' `file_ref`.
 *
 * The two TAX REPORTS (`/admin/reports/vat-register`, `/admin/reports/wht-payees`) come through the
 * same parser with `ext: "csv"`. They are not bank files and their server-side names are ordinary
 * (`vat-register-2026-09.csv`), but the header handling — a hostile or mangled `Content-Disposition`
 * reaching `<a download>` — is the identical problem, and a second parser is how one of the two
 * copies later stops rejecting `../`.
 */

/** Longest name we will accept from the header. The real one is 34 chars
 *  (`SCB_file_reference_` + 12 + `.txt`); anything near this cap is not the bank's name. */
const MAX_FILENAME_LENGTH = 100;

/**
 * `filename*=UTF-8''…` (RFC 5987 / RFC 6266 §4.3) — percent-encoded, and preferred over the plain
 * `filename` when both are present. The `[^;]+` stops at the next header parameter.
 */
const EXTENDED_PARAM = /(?:^|;)\s*filename\*\s*=\s*([^;]+)/iu;

/** `filename="…"` — the quoted form the payment service actually emits today. */
const QUOTED_PARAM = /(?:^|;)\s*filename\s*=\s*"([^"]*)"/iu;

/** `filename=….txt` — the unquoted token form, allowed by RFC 6266 and emitted by some proxies. */
const BARE_PARAM = /(?:^|;)\s*filename\s*=\s*([^;"]+)/iu;

/**
 * Everything a filename must never contain: C0/C1 control characters (a CR/LF or NUL here is never
 * legitimate — it is header-injection debris) plus the characters Windows and macOS reject in a
 * name. Removed rather than rejected on, so one stray byte does not cost us the bank's reference.
 *
 * Operates on code points (`u` flag) — the transport is UTF-8 and the app's text is Thai, so a
 * filename is never sliced or indexed by byte anywhere in this module.
 */
const FORBIDDEN_CHARS = /[\u0000-\u001F\u007F-\u009F<>:"|?*]/gu;

/**
 * The extension the CALLER knows the endpoint produces — `txt` for an SCB upload file, `csv` for a
 * tax report. Insisting on it is the parser's last check: an endpoint that only ever emits one kind
 * of file has no business handing the browser anything else, so a swapped name (an `.exe` from a
 * hostile intermediary, or simply the wrong response landing on the wrong screen) falls back to our
 * own name instead of being saved under theirs.
 */
export type DownloadExt = "txt" | "csv";

/** A real name with a stem, ending in the expected extension — what rejects "", ".", "..", ".txt"
 *  and any extension the caller did not ask for. Pre-built per extension, so the parser never
 *  compiles a pattern out of a value at call time. */
const EXTENSION_SHAPE: Record<DownloadExt, RegExp> = {
  txt: /^[^.].*\.txt$/iu,
  csv: /^[^.].*\.csv$/iu,
};

/**
 * Pull a safe download filename out of a `Content-Disposition` header value.
 *
 * Returns `null` — meaning "use the fallback" — whenever the header is absent, carries no
 * `filename`, or carries one we are not willing to hand to the browser. It is never an error for
 * this to fail: an off-origin deployment (`NEXT_PUBLIC_API_BASE_URL`) whose CORS response omits
 * `Access-Control-Expose-Headers: Content-Disposition`, or a proxy that strips the header, both
 * land here legitimately.
 *
 * Defensive because the value ends up in `<a download>`: we take only the last path segment (so
 * `../../…` or `C:\…` collapses to a bare name and can never steer where the browser writes),
 * scrub control/illegal characters, cap the length, and insist on a real stem carrying the
 * extension the caller expects — the only thing that endpoint ever produces.
 */
export function parseContentDispositionFilename(
  header: string | null | undefined,
  ext: DownloadExt = "txt",
): string | null {
  if (!header) return null;

  const raw =
    decodeExtendedParam(EXTENDED_PARAM.exec(header)?.[1]) ??
    QUOTED_PARAM.exec(header)?.[1] ??
    BARE_PARAM.exec(header)?.[1];
  if (raw === undefined) return null;

  // Last segment only: a directory traversal in the header must not survive as one.
  const base = (raw.split(/[/\\]/u).pop() ?? "").replace(FORBIDDEN_CHARS, "").trim();

  if (base.length === 0 || base.length > MAX_FILENAME_LENGTH) return null;
  if (!EXTENSION_SHAPE[ext].test(base)) return null;

  return base;
}

/**
 * Decode the RFC 5987 extended value `charset'lang'pct-encoded`. Only the percent-encoded part is
 * decoded; a malformed escape (`%zz`) throws `URIError`, which means "unparseable header" here, not
 * a crash in the download path.
 */
function decodeExtendedParam(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  const parts = value.trim().split("'");
  if (parts.length < 3) return undefined; // not the extended form after all
  try {
    return decodeURIComponent(parts.slice(2).join("'"));
  } catch {
    return undefined;
  }
}

/**
 * Which money stream a fallback name belongs to. A closed union rather than a free string: the three
 * streams are SEPARATE files with separate batch tables, and a payout file landing in Downloads
 * under a refund's name (or vice versa) is exactly the confusion this module exists to prevent.
 *
 * `deduction` is the platform-cut sweep — and it is the one whose name matters MOST to get right,
 * because it is the only file of the three that does not pay anybody: it moves the company's own
 * money between the company's own accounts. Mistaking it for a payout file at upload time would send
 * the wrong file to the bank under a reference that already claims the cut was collected.
 */
export type FileStream = "payout" | "refund" | "deduction";

/**
 * The name to save under when the header gives us nothing usable — the same date-stamped name this
 * screen used before, kept as the last resort so an export always downloads.
 *
 * Deliberately NOT in `copy.ts`: a filename is an identifier the operator matches against the SCB
 * Business Net portal, not UI prose. A Thai/English pair would mean the same batch downloads under
 * two different names depending on the admin's language toggle.
 */
export function fallbackDownloadName(
  stream: FileStream = "payout",
  now: Date = new Date(),
): string {
  return `SCB_${stream}_${now.toISOString().slice(0, 10)}.txt`;
}

/** Which tax report a CSV fallback name belongs to. Same closed-union reasoning as [FileStream]:
 *  these two files are transcribed onto DIFFERENT government forms, and one saved under the other's
 *  name is a filing error waiting in a Downloads folder. */
export type ReportKind = "vat-register" | "wht-payees";

/**
 * The fallback name for a tax-report CSV, mirroring the server's own (`vat-register-2026-09.csv`).
 *
 * The FILING PERIOD, not today's date — unlike the bank files, whose fallback is date-stamped
 * because their identity is the bank reference the header carries. A tax report's identity IS its
 * month: two downloads of the same period are the same document, and a report saved under the day it
 * was pulled tells an accountant nothing about which return it belongs to. `month` is the `YYYY-MM`
 * the picker holds; anything else is refused back to a bare stem rather than smuggled into a
 * filename.
 */
export function fallbackReportName(kind: ReportKind, month: string): string {
  return /^\d{4}-\d{2}$/u.test(month) ? `${kind}-${month}.csv` : `${kind}.csv`;
}
