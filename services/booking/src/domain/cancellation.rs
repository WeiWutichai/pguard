//! PURE cancellation-reason rules. No DB/HTTP imports — 100% unit-testable (the only shared
//! import is the error TYPE, like [`crate::domain::progress`]).
//!
//! Both terminal "the job did not happen" transitions carry a MANDATORY reason:
//!   * `cancel`  — the customer, PRE-ARRIVAL (`requested`/`accepted`/`en_route` → `cancelled`)
//!   * `decline` — the ASSIGNED guard withdrawing pre-arrival (`accepted`/`en_route` → `declined`)
//!
//! The two code sets are DIFFERENT and must not be interchangeable: "sick" is not a thing a
//! customer can be on a booking, and "changed_plan" is not a guard's excuse. Sending the other
//! endpoint's code is therefore an INVALID reason (400), not a silently-accepted one — otherwise
//! the analytics/report grouping would mix two vocabularies.
//!
//! What is persisted is the STABLE CODE, never localized text: the app renders the Thai/English
//! label from the code, so re-wording a label never rewrites history (migration 0009).

use shared::error::AppError;

use crate::domain::state::BookingStatus;

/// Machine-readable `error.code` for a missing / unknown-for-this-endpoint reason. Clients
/// branch on this instead of the English message (`AppError::BadRequestCode`).
pub const CANCEL_REASON_REQUIRED_CODE: &str = "CANCEL_REASON_REQUIRED";

/// Machine-readable `error.code` for `reason = "other"` with no note: the free-text elaboration
/// is what makes "other" useful to support, so a blank one is refused.
pub const CANCEL_NOTE_REQUIRED_CODE: &str = "CANCEL_NOTE_REQUIRED";

/// Max characters for the optional free-text note. Counted in CHARACTERS (`chars().count()`,
/// not bytes) — Thai is multi-byte, so a byte cap would silently give Thai users a third of the
/// room. Mirrors [`crate::domain::progress::MAX_NOTE_CHARS`] (2000 there: an hourly check-in is
/// a work log; a cancellation note is one sentence) and the DB backstop
/// `chk_bookings_cancellation_note_len`.
pub const MAX_CANCELLATION_NOTE_CHARS: usize = 500;

/// The free-text escape hatch present in BOTH sets — the one code that REQUIRES a note.
pub const REASON_OTHER: &str = "other";

/// SYSTEM cancellation reason — a booking cancelled by the background scheduler, NOT by a human
/// (ISSUE 1: an OPEN request whose scheduled window ended with no guard). It is deliberately in
/// NEITHER endpoint's vocabulary (`validate_cancellation` never yields it) — only the sweep
/// constructs a [`Cancellation`] with it directly. A system cancel never charges a fee (the sweep
/// passes `is_admin = true`, so `charge_cancel_fee` is false) and its stable code lets the
/// customer's cancellation notice localize to "หมดเวลา"/"expired" rather than a change-of-mind copy.
pub const SYSTEM_EXPIRED_REASON: &str = "system_expired";

/// Reasons a CUSTOMER may cancel with (`PUT /bookings/{id}/cancel`).
pub const CUSTOMER_CANCEL_REASONS: [&str; 4] = ["changed_plan", "mistake", "not_needed", "other"];

/// Reasons the ASSIGNED GUARD may withdraw with (`PUT /bookings/{id}/decline`).
pub const GUARD_DECLINE_REASONS: [&str; 4] = ["emergency", "sick", "cannot_reach", "other"];

/// WHICH vocabulary a reason is validated against — one per endpoint.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReasonSet {
    /// `PUT /bookings/{id}/cancel` — the customer's codes.
    CustomerCancel,
    /// `PUT /bookings/{id}/decline` — the assigned guard's codes.
    GuardDecline,
}

impl ReasonSet {
    /// The allowed codes for this endpoint.
    pub fn codes(self) -> &'static [&'static str] {
        match self {
            ReasonSet::CustomerCancel => &CUSTOMER_CANCEL_REASONS,
            ReasonSet::GuardDecline => &GUARD_DECLINE_REASONS,
        }
    }
}

/// The reason set the given TARGET status expects, or `None` for a status that carries no
/// cancellation reason at all (the whole happy path). Single source of truth for "is this a
/// reason-bearing transition?" — used by the event mapper so a stray reason can never ride a
/// non-cancellation event.
pub fn set_for_target(new_status: BookingStatus) -> Option<ReasonSet> {
    match new_status {
        BookingStatus::Cancelled => Some(ReasonSet::CustomerCancel),
        BookingStatus::Declined => Some(ReasonSet::GuardDecline),
        _ => None,
    }
}

/// A validated cancellation: the stable code (borrowed from the allowlist, so it can only ever
/// be one of the known codes) plus the trimmed, length-checked note.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cancellation {
    /// The stable code — always a `&'static str` FROM the endpoint's allowlist, never client text.
    pub reason: &'static str,
    /// The trimmed free text; `None` when the client sent nothing (or only whitespace).
    pub note: Option<String>,
}

/// Validate a cancel/decline body against `set`.
///
/// Rules (the shared contract):
/// - `reason` missing / not in THIS endpoint's set (incl. the OTHER endpoint's codes) → 400
///   [`CANCEL_REASON_REQUIRED_CODE`];
/// - `note` is trimmed, and blank becomes `None`;
/// - a note longer than [`MAX_CANCELLATION_NOTE_CHARS`] (counted in chars) → 400 `BadRequest`;
/// - `reason == "other"` with no note left after trimming → 400 [`CANCEL_NOTE_REQUIRED_CODE`].
///
/// The returned code is the `&'static str` from the allowlist, NOT the caller's buffer — the
/// persisted/emitted value is provably one of the known codes.
pub fn validate_cancellation(
    set: ReasonSet,
    reason: Option<&str>,
    note: Option<&str>,
) -> Result<Cancellation, AppError> {
    // 1. The code must be in THIS endpoint's vocabulary. A missing reason and the other
    //    endpoint's code fail identically — both are "not a reason this endpoint accepts".
    let reason = reason.map(str::trim).unwrap_or_default();
    let code = set
        .codes()
        .iter()
        .copied()
        .find(|c| *c == reason)
        .ok_or_else(|| AppError::BadRequestCode {
            code: CANCEL_REASON_REQUIRED_CODE,
            message: "A valid cancellation reason is required".to_string(),
        })?;

    // 2. Trim first, blank → None: the trimmed value is what is persisted, so it is also what
    //    the length cap (and the DB CHECK on the stored text) must measure.
    let note = note.map(str::trim).filter(|n| !n.is_empty());
    if let Some(note) = note {
        if note.chars().count() > MAX_CANCELLATION_NOTE_CHARS {
            return Err(AppError::BadRequest(format!(
                "note must be at most {MAX_CANCELLATION_NOTE_CHARS} characters"
            )));
        }
    }

    // 3. "other" is only informative WITH the free text.
    if code == REASON_OTHER && note.is_none() {
        return Err(AppError::BadRequestCode {
            code: CANCEL_NOTE_REQUIRED_CODE,
            message: "A note is required when the reason is 'other'".to_string(),
        });
    }

    Ok(Cancellation {
        reason: code,
        note: note.map(str::to_string),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code_of(err: &AppError) -> Option<&'static str> {
        match err {
            AppError::BadRequestCode { code, .. } => Some(code),
            _ => None,
        }
    }

    // ----- the two vocabularies are disjoint per endpoint -----

    #[test]
    fn customer_codes_are_accepted_on_cancel() {
        for reason in ["changed_plan", "mistake", "not_needed"] {
            let c = validate_cancellation(ReasonSet::CustomerCancel, Some(reason), None)
                .unwrap_or_else(|e| panic!("{reason} must be a valid customer reason: {e}"));
            assert_eq!(c.reason, reason);
            assert_eq!(c.note, None);
        }
    }

    #[test]
    fn guard_codes_are_accepted_on_decline() {
        for reason in ["emergency", "sick", "cannot_reach"] {
            let c = validate_cancellation(ReasonSet::GuardDecline, Some(reason), None)
                .unwrap_or_else(|e| panic!("{reason} must be a valid guard reason: {e}"));
            assert_eq!(c.reason, reason);
            assert_eq!(c.note, None);
        }
    }

    #[test]
    fn a_guard_code_is_rejected_on_cancel_and_vice_versa() {
        // The sets are NOT interchangeable — the wrong endpoint's code is as invalid as junk.
        for reason in ["emergency", "sick", "cannot_reach"] {
            let err = validate_cancellation(ReasonSet::CustomerCancel, Some(reason), None)
                .expect_err("a guard code must not pass /cancel");
            assert_eq!(code_of(&err), Some(CANCEL_REASON_REQUIRED_CODE), "{reason}");
        }
        for reason in ["changed_plan", "mistake", "not_needed"] {
            let err = validate_cancellation(ReasonSet::GuardDecline, Some(reason), None)
                .expect_err("a customer code must not pass /decline");
            assert_eq!(code_of(&err), Some(CANCEL_REASON_REQUIRED_CODE), "{reason}");
        }
    }

    #[test]
    fn other_is_shared_by_both_sets() {
        for set in [ReasonSet::CustomerCancel, ReasonSet::GuardDecline] {
            let c = validate_cancellation(set, Some(REASON_OTHER), Some("รถเสีย"))
                .unwrap_or_else(|e| panic!("{set:?}: other + note must pass: {e}"));
            assert_eq!(c.reason, "other");
            assert_eq!(c.note.as_deref(), Some("รถเสีย"));
        }
    }

    // ----- missing / unknown reason -----

    #[test]
    fn missing_or_unknown_reason_is_reason_required() {
        for bad in [None, Some(""), Some("   "), Some("bogus"), Some("Other")] {
            let err = validate_cancellation(ReasonSet::CustomerCancel, bad, None)
                .expect_err("an absent/unknown reason must be rejected");
            assert_eq!(
                code_of(&err),
                Some(CANCEL_REASON_REQUIRED_CODE),
                "reason {bad:?}"
            );
        }
    }

    #[test]
    fn reason_is_trimmed_before_matching() {
        let c = validate_cancellation(ReasonSet::CustomerCancel, Some("  mistake "), None)
            .expect("surrounding whitespace must not invalidate a good code");
        assert_eq!(c.reason, "mistake");
    }

    // ----- the note -----

    #[test]
    fn other_without_a_note_is_note_required() {
        for blank in [None, Some(""), Some("   \n\t")] {
            let err = validate_cancellation(ReasonSet::GuardDecline, Some(REASON_OTHER), blank)
                .expect_err("'other' needs the free text");
            assert_eq!(
                code_of(&err),
                Some(CANCEL_NOTE_REQUIRED_CODE),
                "note {blank:?}"
            );
        }
    }

    #[test]
    fn blank_note_becomes_none() {
        let c = validate_cancellation(ReasonSet::CustomerCancel, Some("mistake"), Some("   "))
            .expect("a blank note on a non-other reason is simply absent");
        assert_eq!(c.note, None);
    }

    #[test]
    fn note_is_trimmed() {
        let c = validate_cancellation(ReasonSet::CustomerCancel, Some("mistake"), Some(" ผิดครับ "))
            .expect("valid");
        assert_eq!(c.note.as_deref(), Some("ผิดครับ"));
    }

    #[test]
    fn note_capped_in_characters_not_bytes() {
        // Thai is 3 bytes/char: exactly the cap passes (1500 bytes), one more fails — a byte
        // cap would have rejected the first.
        let ok = "ก".repeat(MAX_CANCELLATION_NOTE_CHARS);
        assert!(
            validate_cancellation(ReasonSet::CustomerCancel, Some("mistake"), Some(&ok)).is_ok()
        );
        let too_long = "ก".repeat(MAX_CANCELLATION_NOTE_CHARS + 1);
        let err =
            validate_cancellation(ReasonSet::CustomerCancel, Some("mistake"), Some(&too_long))
                .expect_err("over the cap");
        assert!(
            matches!(err, AppError::BadRequest(_)),
            "expected a plain BadRequest, got {err:?}"
        );
        // Trailing whitespace does NOT count toward the cap (trim happens first).
        let padded = format!("  {ok}  ");
        assert!(
            validate_cancellation(ReasonSet::CustomerCancel, Some("mistake"), Some(&padded))
                .is_ok()
        );
    }

    // ----- which transitions carry a reason -----

    #[test]
    fn only_cancelled_and_declined_carry_a_reason() {
        assert_eq!(
            set_for_target(BookingStatus::Cancelled),
            Some(ReasonSet::CustomerCancel)
        );
        assert_eq!(
            set_for_target(BookingStatus::Declined),
            Some(ReasonSet::GuardDecline)
        );
        for status in [
            BookingStatus::Requested,
            BookingStatus::Accepted,
            BookingStatus::EnRoute,
            BookingStatus::Arrived,
            BookingStatus::PendingCompletion,
            BookingStatus::Completed,
        ] {
            assert_eq!(set_for_target(status), None, "{status} carries no reason");
        }
    }
}
