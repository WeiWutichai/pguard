/**
 * Handing a generated file to the browser — the ONE place any of the three money screens turns a
 * response body into something in the admin's Downloads folder.
 *
 * It lives here beside `download-name.ts` for the same reason that module does: the SCB bank-file
 * screens (guard payout, customer refund, platform-cut sweep) and the two tax reports all end in
 * exactly this gesture, and a per-screen copy of it is how one of them quietly loses the object URL,
 * the charset, or — the expensive one — the byte-order mark.
 *
 * TWO functions, and the split is NOT cosmetic:
 *
 *  * [saveText] is for the SCB upload files. Those are served as `text/plain`, UTF-8, deliberately
 *    WITHOUT a BOM (the bank's parser would read one as data), so decoding to a string and
 *    re-encoding here is lossless.
 *
 *  * [saveBlob] is for the tax-report CSVs, and they must NOT go through a string. The payment
 *    service prepends a UTF-8 BOM on purpose — without it Excel on Thai Windows renders every Thai
 *    name in the file as mojibake — and `Response.text()` performs a UTF-8 decode, which by
 *    specification STRIPS a leading BOM. Reading those responses as text and re-saving them would
 *    therefore silently undo the server's fix; fetching them as a `Blob` keeps the bytes verbatim.
 */

/** Give the browser a blob under `filename`, byte for byte. The blob's own type is kept — for a
 *  fetched response that is the server's `Content-Type`, which is the honest one. */
export function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/** Give the browser a UTF-8 text file (the SCB upload files' `.txt`). */
export function saveText(text: string, filename: string): void {
  saveBlob(new Blob([text], { type: "text/plain;charset=utf-8" }), filename);
}
