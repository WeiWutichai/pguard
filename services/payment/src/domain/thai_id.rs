//! PURE Thai national-ID (เลขประจำตัวประชาชน) check digit — no DB/HTTP. 100% unit-testable.
//!
//! WHY THIS LIVES IN payment AT ALL, when profile already has it (`services/profile/src/domain/
//! validate.rs::thai_national_id_check_digit_ok`). This is a deliberate 6-line DUPLICATE, not an
//! oversight, and the trade is worth stating so nobody "de-duplicates" it into a shared crate or —
//! far worse — a cross-service call:
//!
//!  * profile enforces the checksum at its WRITE boundary. That protects values written AFTER the
//!    rule existed, through THAT endpoint. It says nothing about a 13-digit tax id that predates the
//!    validation, was seeded, was restored from a backup, or arrived by any other path.
//!  * payment is where the number stops being an identifier and becomes a DESTINATION: a 13-digit
//!    tax id is written into `TXNDET` field 2 as a PromptPay `NAT` proxy, and PromptPay credits
//!    whoever owns that id. A mistyped digit does not fail — it pays a STRANGER, irreversibly.
//!
//! Defence in depth on a money path is worth six duplicated lines; a shared crate (or a service call
//! from inside the export loop) would couple the payout run to profile's release cycle and add a
//! failure mode to the one code path that must never guess. The algorithm is a fixed, published
//! national standard: it cannot drift out from under either copy.

/// The weights of the Thai national-ID mod-11 check digit: 13, 12, … 2 over the first TWELVE digits.
/// Their count also fixes the length: `WEIGHTS.len() + 1` = 13.
const WEIGHTS: [u32; 12] = [13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2];

/// Number of digits in a Thai national id (the 12 weighted digits + the check digit).
pub const NATIONAL_ID_DIGITS: usize = WEIGHTS.len() + 1;

/// Whether `digits` is a 13-digit Thai national id whose mod-11 check digit is right.
///
/// `digits` must already be the DIGITS-ONLY form (callers strip separators with
/// [`crate::domain::scb_export::digits_only`] first). Anything that is not exactly 13 ASCII digits
/// returns `false` rather than panicking — this runs in a request path, and no money-path function
/// here indexes or slices its way into a panic.
///
/// ```text
/// sum   = Σ digit[i] × (13 − i)   over the first TWELVE digits (weights 13 → 2)
/// check = (11 − (sum mod 11)) mod 10
/// valid iff check == digit[12]
/// ```
///
/// Pure.
pub fn national_id_check_digit_ok(digits: &str) -> bool {
    let d: Vec<u32> = digits.chars().filter_map(|c| c.to_digit(10)).collect();
    // `filter_map` silently drops a non-digit (and `to_digit(10)` would accept no non-ASCII digit
    // anyway), so also require that NOTHING was dropped — `12345678901X` must fail, not shrink.
    if d.len() != NATIONAL_ID_DIGITS || d.len() != digits.chars().count() {
        return false;
    }
    // Max sum is 9 × (13+12+…+2) = 9 × 90 = 810, so no overflow; `sum % 11` ∈ [0,10], so the
    // `11 - …` below never underflows.
    let sum: u32 = WEIGHTS
        .iter()
        .zip(&d)
        .map(|(weight, digit)| weight * digit)
        .sum();
    let check = (11 - (sum % 11)) % 10;
    // `get` rather than `d[12]`: the length is already proven, but a money path never indexes.
    d.get(NATIONAL_ID_DIGITS - 1) == Some(&check)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_checksum_valid_national_id_passes_and_a_transposed_digit_does_not() {
        // Both valid fixtures are deliberately a VISIBLE `0123456789…` / `1234567890…` keyboard
        // run, and every future one must be too. A 13-digit number that satisfies mod-11 *and*
        // opens with a real province/district registration prefix is indistinguishable from a
        // living person's เลขประจำตัวประชาชน — and this file is the money path where that number
        // becomes a PromptPay destination. A fixture that could be mistaken for someone's actual id
        // is PII committed to git history forever (PDPA); it has to be wrong at a glance.
        //
        // Worked BY HAND (the same two the profile-side copy is checked against, so the duplicate
        // provably agrees):
        //   0123456789016 → sum 302, 302 mod 11 = 5, (11−5) mod 10 = 6 = the last digit ✓
        //   1234567890121 → 1×13 + 2×12 + 3×11 + 4×10 + 5×9 + 6×8 + 7×7 + 8×6 + 9×5 + 0×4 + 1×3
        //                   + 2×2 = 13+24+33+40+45+48+49+48+45+0+3+4 = 352,
        //                   352 mod 11 = 0, (11−0) mod 10 = 1 = the last digit ✓
        assert!(national_id_check_digit_ok("0123456789016"));
        assert!(national_id_check_digit_ok("1234567890121"));
        // One wrong check digit — the everyday typo, and the one that credits a stranger.
        assert!(!national_id_check_digit_ok("0123456789015"));
        // The leading two digits transposed (1,2 → 2,1) — a keying error the SHAPE cannot catch.
        // It moves the sum by (2×13 + 1×12) − (1×13 + 2×12) = 38 − 37 = +1: 352 → 353, and
        // 353 mod 11 = 1, so the check digit becomes (11−1) mod 10 = 0 ≠ 1 ✗. Same invalid twin
        // profile's `validate_guard_req` rejects, so both copies provably agree on the failure too.
        assert!(!national_id_check_digit_ok("2134567890121"));
    }

    #[test]
    fn the_fixture_ids_used_across_these_tests_are_genuinely_valid() {
        // The goldens + the export tests model real people, so their ids must satisfy the rule the
        // export now enforces. Working, by hand, for each:
        //   123456789012 → sum 352, 352 mod 11 = 0, (11−0) mod 10 = 1  → 1234567890121
        //   987654321098 → sum 508, 508 mod 11 = 2, (11−2) mod 10 = 9  → 9876543210989
        //   111111111111 → sum  90,  90 mod 11 = 2, (11−2) mod 10 = 9  → 1111111111119
        //   222222222222 → sum 180, 180 mod 11 = 4, (11−4) mod 10 = 7  → 2222222222227
        //   333333333333 → sum 270, 270 mod 11 = 6, (11−6) mod 10 = 5  → 3333333333335
        for id in [
            "1234567890121",
            "9876543210989",
            "1111111111119",
            "2222222222227",
            "3333333333335",
        ] {
            assert!(national_id_check_digit_ok(id), "{id} must be valid");
        }
        // …and the shapes they REPLACED (a repeated digit or a naive count-up) are exactly what the
        // rule rejects — which is why the fixtures had to move.
        for bogus in [
            "1234567890123",
            "9876543210987",
            "1111111111111",
            "2222222222222",
            "3333333333333",
        ] {
            assert!(!national_id_check_digit_ok(bogus), "{bogus} must fail");
        }
    }

    #[test]
    fn the_company_tin_in_the_fixtures_passes_too() {
        // 010555123456 → sum 224, 224 mod 11 = 4, (11−4) mod 10 = 7 → 0105551234567 ✓.
        // A juristic-person TIN is NOT gated by this rule in production (see profile's
        // `validate_tax_id`) — it is a tax REFERENCE, never a destination — but the fixture happens
        // to be a well-formed number, and asserting so keeps the goldens honest.
        assert!(national_id_check_digit_ok("0105551234567"));
    }

    #[test]
    fn anything_that_is_not_thirteen_ascii_digits_is_false_never_a_panic() {
        for bad in [
            "",
            "123",
            "12345678901234",    // 14
            "123456789012",      // 12
            "1-2345-67890-12-1", // separators must be stripped by the CALLER
            "12345678901X",      // a letter
            "๑๒๓๔๕๖๗๘๙๐๑๒๑",     // Thai digits are not ASCII digits
            "0812345678",        // a MOB proxy is not a national id
        ] {
            assert!(!national_id_check_digit_ok(bad), "{bad:?} must be false");
        }
    }

    #[test]
    fn the_outer_mod_ten_is_load_bearing_at_both_ends() {
        // `check = (11 − k) % 10` folds the two out-of-range results back into a single digit, and
        // both ends are reachable, so both are pinned here:
        //   k = 1 → 11−1 = 10 → check 0  ·  000000000006 → sum 12, 12 mod 11 = 1 → 0000000000060
        //   k = 0 → 11−0 = 11 → check 1  ·  123456789012 → sum 352, 352 mod 11 = 0 → 1234567890121
        assert!(national_id_check_digit_ok("0000000000060"));
        assert!(
            !national_id_check_digit_ok("0000000000000"),
            "…not 10, and not 0-is-always-fine"
        );
        assert!(national_id_check_digit_ok("1234567890121"));
        assert!(!national_id_check_digit_ok("1234567890120"));
    }
}
