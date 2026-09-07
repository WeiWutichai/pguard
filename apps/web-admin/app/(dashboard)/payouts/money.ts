/**
 * Money helpers for the payout screens.
 *
 * Every money field on this API is an EXACT decimal carried as a string ("1455.00") — never a
 * float — because the same numbers are `rust_decimal::Decimal` on the server and land verbatim in
 * an SCB credit line. Nothing here ever produces a value that is SENT anywhere: these totals are
 * shown so an admin can confirm what they are about to do against a number. The amounts that reach
 * the bank come from the server, which sums them in decimal.
 */

/**
 * Σ a column of 2dp decimal strings, back as a 2dp string.
 *
 * Goes through `Number` (binary floating point) and is pulled back onto 2dp by `toFixed`, which is
 * why the doc above insists this is display-only: a hundred `0.1`s do not add up exactly in
 * binary, and the rounding hides that — acceptable for a subtotal an operator reads, not for a
 * figure anyone pays. A non-numeric entry contributes 0 rather than poisoning the whole sum with
 * `NaN` (one bad row must not blank the total the admin is confirming against).
 */
export function sumDecimalStrings(values: readonly string[]): string {
  return values.reduce((acc, v) => acc + (Number(v) || 0), 0).toFixed(2);
}

/**
 * The SIGN of one exact-decimal string — `-1`, `0` or `1` — decided on the TEXT, never through
 * `Number`.
 *
 * Unlike [sumDecimalStrings] this one gates behaviour rather than decorating a read-out: it is what
 * says whether the platform-cut sweep has a transferable amount at all (SCB's credit-line minimum is
 * ฿0.01, so "positive" and "sendable" are the same question), and whether a billed-but-uncollected
 * figure exists and has to be explained. A float round-trip has no business anywhere near that
 * decision — `Number("0.005")` is not 0, and a value the server called zero must read as zero here.
 *
 * A string that is not a plain decimal — an empty body, a truncated response, anything unexpected —
 * reports `0`, which is the SAFE direction for every caller: no export button is enabled and no
 * "money is missing" warning is invented out of a value we could not read.
 */
export function signOfDecimalString(value: string): -1 | 0 | 1 {
  const text = value.trim();
  if (!/^-?\d+(\.\d+)?$/u.test(text)) return 0;
  // Leading/trailing zeros and a "-0.00" all collapse here: a decimal is non-zero only if some digit
  // is, whatever the point and the sign do.
  if (!/[1-9]/u.test(text)) return 0;
  return text.startsWith("-") ? -1 : 1;
}
