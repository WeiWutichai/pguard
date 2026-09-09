//! PURE CSV rendering for the two TAX REPORTS (ภ.พ.30 output-VAT register, ภ.ง.ด.3/53 payee list).
//! No DB, no HTTP; 100% unit-testable.
//!
//! It is generated SERVER-SIDE, and that is a decision rather than an accident: the browser cannot
//! escape what it never sees. String-concatenating a CSV in the admin panel puts the escaping rules
//! in the one place least able to test them, and a Thai name containing a comma silently shifts
//! every later column of that row in the accountant's spreadsheet — the same class of bug as an
//! unescaped `|` in the SCB file next door, with the same silence.
//!
//! Three rules, all of them load-bearing:
//!
//!  1. **RFC 4180 quoting.** A field containing `,`, `"`, CR or LF is wrapped in double quotes and
//!     its own quotes are doubled. Rows are joined with CRLF, which is what the RFC specifies and
//!     what Excel writes itself.
//!  2. **A UTF-8 BOM leads the file.** Excel on Thai Windows does NOT detect UTF-8 from content: it
//!     falls back to the system ANSI code page (CP874) and every Thai name arrives as mojibake. The
//!     three bytes `EF BB BF` are the only thing that makes it read the file as UTF-8. LibreOffice
//!     and Google Sheets accept the BOM happily, so it costs nothing there. Do not "clean it up".
//!  3. **Formula neutralisation.** A field beginning `=`, `+`, `-` or `@` is executed as a FORMULA
//!     when the sheet is opened — and these reports carry customer and guard names straight out of
//!     the profile store, which anyone can type into. Such a field is prefixed with an apostrophe,
//!     which Excel reads as "this is text" and does not display.
//!     …EXCEPT when the field is a NUMBER: a negative amount legitimately starts with `-`, and
//!     quoting it as text would break the SUM the accountant is opening the file to do. So the guard
//!     is applied only to fields that are not numeric literals — see [`is_numeric_literal`].
//!     The lead character is found AFTER skipping leading whitespace and control characters, which
//!     is the whole of OWASP's CSV-injection bypass list — see [`leads_a_formula`].

/// The three bytes Excel needs before it will read a file as UTF-8 (rule 2 above).
pub const UTF8_BOM: &str = "\u{feff}";

/// RFC 4180 record separator. Excel writes CRLF; so do we.
const CSV_NEWLINE: &str = "\r\n";

/// The characters Excel treats as the start of a formula (rule 3 above).
const FORMULA_LEAD: [char; 4] = ['=', '+', '-', '@'];

/// Whether `value` is a plain number — an optional sign, digits, at most one decimal point, and
/// nothing else. Only these may keep a leading `-`/`+` without the text-guard apostrophe, because
/// only these are meant to be summed.
///
/// Deliberately narrow: no thousands separators, no exponents, no currency symbols. Everything this
/// module emits as a number comes from `scb_export::format_amount` (a bare `-?d+.dd`) or from an
/// integer count, so a value that does not match this shape is not one of ours and is treated as
/// text. Pure.
pub fn is_numeric_literal(value: &str) -> bool {
    let body = value.strip_prefix(['-', '+']).unwrap_or(value);
    if body.is_empty() {
        return false;
    }
    let mut seen_dot = false;
    let mut seen_digit = false;
    for ch in body.chars() {
        match ch {
            '0'..='9' => seen_digit = true,
            '.' if !seen_dot => seen_dot = true,
            _ => return false,
        }
    }
    seen_digit
}

/// Whether `value`'s FIRST MEANINGFUL character is one Excel reads as the start of a formula.
///
/// `starts_with(FORMULA_LEAD)` on the raw string is not enough, and the gap is a real bypass rather
/// than a theoretical one: a spreadsheet importer strips leading whitespace and control bytes from a
/// cell BEFORE it decides whether the cell is a formula, so `"\t=cmd|'/c calc'!A1"` reaches the
/// parser as `=cmd…` and is executed. TAB (0x09) and CR (0x0D) are on OWASP's CSV-injection list for
/// exactly that reason, and LF, VT (0x0B), FF (0x0C) and a plain space behave the same way.
///
/// SKIPPING, NOT STRIPPING, is the deliberate choice. This module already refuses to trim padding
/// ("a silently trimmed value in a tax report is a changed value" — see the quoting rule below), and
/// a payee name that goes onto a ภ.ง.ด. return must reach the accountant byte for byte. So the
/// padding is preserved and the apostrophe is prepended IN FRONT of it: Excel still reads the cell
/// as text, and nothing was rewritten. Enumerating a longer character set instead would be a fresh
/// bypass every time a spreadsheet added one — `is_whitespace` ∪ `is_control` is the whole class.
///
/// Note the interaction with [`is_numeric_literal`], which is deliberately tested on the RAW value:
/// `" -2.50"` is therefore NOT a number here and DOES get the apostrophe. Nothing this module emits
/// as a number is ever padded (they all come from `scb_export::format_amount`), so the only values
/// that hit that arm are free text that merely looks numeric — which is exactly what should be
/// guarded. Pure.
pub fn leads_a_formula(value: &str) -> bool {
    value
        .chars()
        .find(|c| !c.is_whitespace() && !c.is_control())
        .is_some_and(|c| FORMULA_LEAD.contains(&c))
}

/// Render ONE field: neutralise a leading formula character (unless it is a number), then quote per
/// RFC 4180 when the value contains a delimiter, a quote or a line break. Pure.
pub fn field(value: &str) -> String {
    // Rule 3 first — the apostrophe it may add is itself harmless to the quoting below.
    let guarded = if !is_numeric_literal(value) && leads_a_formula(value) {
        format!("'{value}")
    } else {
        value.to_string()
    };
    // Rule 1. LEADING or TRAILING whitespace is quoted too: some parsers strip unquoted padding, and
    // a silently trimmed value in a tax report is a changed value. The padding test reads the
    // ORIGINAL `value`, not `guarded` — the apostrophe rule 3 may have prepended would otherwise
    // hide the very padding that made the value dangerous, and drop the quoting that preserves it.
    // (The delimiter test is the same either way: `'` is none of `, " CR LF`.)
    let needs_quotes = value.contains([',', '"', '\r', '\n'])
        || value.starts_with(char::is_whitespace)
        || value.ends_with(char::is_whitespace);
    if needs_quotes {
        format!("\"{}\"", guarded.replace('"', "\"\""))
    } else {
        guarded
    }
}

/// Render one record: every field escaped, joined with commas. Pure.
pub fn row<S: AsRef<str>>(fields: &[S]) -> String {
    fields
        .iter()
        .map(|f| field(f.as_ref()))
        .collect::<Vec<_>>()
        .join(",")
}

/// Render a whole CSV document: the BOM, the header row, then the data rows, CRLF-separated with a
/// trailing CRLF (RFC 4180 permits it and Excel writes one).
///
/// Takes the rows as slices of already-formatted strings — the money is formatted by
/// `scb_export::format_amount` at the call site, so the two exports and the SCB file itself can
/// never disagree about how a baht amount looks. Pure.
pub fn document<H: AsRef<str>, R: AsRef<str>>(header: &[H], rows: &[Vec<R>]) -> String {
    let mut out = String::with_capacity(UTF8_BOM.len() + 64 * (rows.len() + 1));
    out.push_str(UTF8_BOM);
    out.push_str(&row(header));
    out.push_str(CSV_NEWLINE);
    for r in rows {
        out.push_str(&row(r));
        out.push_str(CSV_NEWLINE);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// THE ESCAPING TEST: a comma, a quote, a newline and Thai text — the four things that break a
    /// hand-rolled CSV, in one row.
    #[test]
    fn a_field_with_a_comma_a_quote_a_newline_and_thai_survives_intact() {
        assert_eq!(
            field("บริษัท รักษาความปลอดภัย จำกัด"),
            "บริษัท รักษาความปลอดภัย จำกัด"
        );
        assert_eq!(
            field("บริษัท, จำกัด"),
            "\"บริษัท, จำกัด\"",
            "a comma forces quoting or every later column shifts"
        );
        assert_eq!(
            field("ชื่อ \"เล่น\""),
            "\"ชื่อ \"\"เล่น\"\"\"",
            "an inner quote is DOUBLED, not backslash-escaped"
        );
        assert_eq!(
            field("99/1 ซอย 5\nแขวงบางกะปิ"),
            "\"99/1 ซอย 5\nแขวงบางกะปิ\"",
            "a newline inside a field must be quoted, and the newline itself is kept"
        );
        assert_eq!(field("a\r\nb"), "\"a\r\nb\"");
        // All four at once, which is the shape a real address field can genuinely take.
        assert_eq!(
            field("ที่อยู่ \"บ้าน\", ซ.1\nกทม"),
            "\"ที่อยู่ \"\"บ้าน\"\", ซ.1\nกทม\""
        );
        // Padding is preserved by quoting rather than silently trimmed by the reader.
        assert_eq!(field(" 1234567890 "), "\" 1234567890 \"");
        // Empty stays empty (an absent address is a blank cell, not a quoted one).
        assert_eq!(field(""), "");
    }

    /// Rule 3 both ways: a name that looks like a formula is neutralised, a negative AMOUNT is not.
    #[test]
    fn a_formula_looking_name_is_neutralised_but_a_negative_amount_stays_a_number() {
        // The attack: a display name typed into a profile, executed when the sheet is opened.
        assert_eq!(field("=1+1"), "'=1+1");
        assert_eq!(field("@SUM(A1:A9)"), "'@SUM(A1:A9)");
        assert_eq!(field("+ชื่อ"), "'+ชื่อ");
        assert_eq!(field("-ชื่อ"), "'-ชื่อ");
        // A formula containing a comma is guarded AND quoted — the two rules compose.
        assert_eq!(
            field("=HYPERLINK(\"a\",\"b\")"),
            "\"'=HYPERLINK(\"\"a\"\",\"\"b\"\")\""
        );

        // …and the cost the guard must NOT impose: a negative amount is what an accountant sums.
        for number in ["-2.50", "-0.01", "0.00", "1746.00", "+3", "-999999999.99"] {
            assert_eq!(field(number), number, "{number} must stay a number");
            assert!(is_numeric_literal(number));
        }
        // Things that merely look numeric are text (and none of them is a shape we emit).
        for text in ["", "-", "+", ".", "1,234.00", "1e5", "๑๒๓", "12.34.56"] {
            assert!(!is_numeric_literal(text), "{text} is not a number");
        }
    }

    /// THE BYPASS. A spreadsheet importer strips leading whitespace/control bytes before deciding
    /// whether a cell is a formula, so a name typed as `"\t=cmd…"` used to sail past a raw
    /// `starts_with` and be EXECUTED when the accountant opened the ภ.ง.ด. payee list.
    ///
    /// Every character on OWASP's list is exercised against every formula lead — a table rather than
    /// a handful of spot checks, because this is the shape of bug that comes back one character at a
    /// time. The apostrophe goes IN FRONT of the padding: the cell reads as text and the stored value
    /// is still there byte for byte, which a tax report requires.
    #[test]
    fn leading_whitespace_or_control_bytes_cannot_smuggle_a_formula_through() {
        // tab, CR, LF, vertical tab, form feed, a plain space — plus a combination, because a real
        // payload pads with whatever the field will accept.
        let pads = ["\t", "\r", "\n", "\u{0b}", "\u{0c}", " ", "\r\n\t  "];
        for pad in pads {
            for lead in ['=', '+', '-', '@'] {
                let payload = format!("{pad}{lead}cmd|'/c calc'!A1");
                assert!(
                    leads_a_formula(&payload),
                    "{pad:?}{lead} must still read as a formula lead"
                );
                let rendered = field(&payload);
                let body = rendered.trim_matches('"');
                assert!(
                    body.starts_with('\''),
                    "the guard must precede the padding, not follow it: {rendered:?}"
                );
                // The value itself is PRESERVED — a tax report may not silently rewrite a payee's
                // name, so the padding survives inside the (possibly quoted) cell.
                assert!(
                    rendered.contains(&payload.replace('"', "\"\"")),
                    "the original value must survive intact: {rendered:?}"
                );
            }
        }
        // …and the four bare leads still behave exactly as before.
        for lead in ['=', '+', '-', '@'] {
            assert!(leads_a_formula(&format!("{lead}SUM(A1)")));
        }
        // Text that merely CONTAINS a lead further in is not a formula and must not be touched.
        for safe in [
            "บริษัท รักษาความปลอดภัย",
            "A=1",
            "\t ชื่อไทย",
            "",
            "   ",
            "\t\r\n",
        ] {
            assert!(!leads_a_formula(safe), "{safe:?} is not a formula");
            assert!(!field(safe).trim_matches('"').starts_with('\''));
        }
        // A padded value that merely LOOKS numeric is text, so it is guarded — and that is correct:
        // nothing this module emits as a number is ever padded.
        assert_eq!(field(" -2.50"), "\"' -2.50\"");
        assert_eq!(field("-2.50"), "-2.50", "a real amount still sums");
    }

    #[test]
    fn a_document_leads_with_the_bom_and_uses_crlf_records() {
        let doc = document(
            &["วันที่", "ชื่อ", "ยอด"],
            &[
                vec!["2026-09-01", "บริษัท, จำกัด", "1070.00"],
                vec!["2026-09-02", "=cmd", "-2.50"],
            ],
        );
        // The BOM is the FIRST thing in the file — without it Excel on Thai Windows renders every
        // Thai column as mojibake.
        assert!(doc.starts_with(UTF8_BOM));
        assert_eq!(
            doc.as_bytes()[..3],
            [0xEF, 0xBB, 0xBF],
            "the BOM must be the three UTF-8 bytes, not some other zero-width character"
        );
        let body = doc.trim_start_matches(UTF8_BOM);
        let lines: Vec<&str> = body.split("\r\n").collect();
        assert_eq!(lines[0], "วันที่,ชื่อ,ยอด");
        assert_eq!(lines[1], "2026-09-01,\"บริษัท, จำกัด\",1070.00");
        assert_eq!(lines[2], "2026-09-02,'=cmd,-2.50");
        assert_eq!(lines[3], "", "trailing CRLF");
        // A header-only report is still a valid file, not an empty response.
        let empty: Vec<Vec<String>> = Vec::new();
        assert_eq!(document(&["a", "b"], &empty), format!("{UTF8_BOM}a,b\r\n"));
    }
}
