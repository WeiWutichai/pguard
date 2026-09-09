//! PURE export-batch lifecycle — no DB, no HTTP. The ONE place that decides whether a status
//! change is legal, so the repo transaction only has to apply it. 100% unit-testable.
//!
//! SHARED BY EVERY MONEY STREAM. A guard-payout file (stream ③), a customer-refund file (stream ①)
//! and a platform-cut sweep (stream ②) walk the *same* path through the bank, so they walk the same
//! table here — only the error CODES and the Thai copy differ, and those hang off [`BatchKind`]. Two
//! copies of a transition table is how the streams drift apart, and the one that drifts is the one
//! that un-marks money it should not have.
//!
//! A generated SCB file walks a real-world path the platform cannot observe: an admin downloads it,
//! uploads it to SCB Business Net by hand, and the bank either takes it or bounces it. The status
//! records where in that path the batch is, and the transitions encode what can honestly follow
//! what:
//!
//! ```text
//!   generated ─→ uploaded ─→ confirmed        (terminal — the bank took the file; money moved)
//!       │            └────→ rejected
//!       │                      │
//!       └──────────────────────┴─────→ voided (terminal — the work went back to the backlog)
//! ```
//!
//! WHY `confirmed` IS TERMINAL, even though "anything can be voided" reads more forgiving: voiding
//! is not a label, it un-marks every item in the batch as settled and puts that obligation back in
//! the payable backlog. Doing that to a batch the bank already settled would pay the same guard —
//! or refund the same customer — a SECOND time. A confirmed batch is money that has left the
//! account; the remedy for one that was wrong is a new correcting transfer, never a void.
//!
//! `rejected` is NOT terminal: the bank refused the file, no money moved, and voiding is exactly
//! what should happen next so the work can ride a fresh batch.

use shared::error::AppError;

/// WHICH money stream's batch a transition is being checked for. It changes NOTHING about what is
/// legal — the table below is the same path through the same bank — only the typed error `code` and
/// the Thai noun the admin reads.
///
/// The codes are per-stream on purpose: a screen handling a refund file must not have to recognise
/// `PAYOUT_…` to tell "already cancelled" from "cannot be re-opened", and the payout's existing
/// codes are a published contract (`contracts/openapi/payment.yaml`) that must not shift underneath
/// the admin panel just because a second stream arrived.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BatchKind {
    /// Stream ③ *ยอดที่โอนให้ รปภ* — the guard-payout file. Items are BOOKINGS.
    Payout,
    /// Stream ① *ยอดที่ต้องโอนคืนกับคนจ้าง* — the customer-refund file. Items are refund OBLIGATIONS
    /// (a `payment.payments` row or a `payment.payment_slips` row).
    Refund,
    /// Stream ② *ยอดที่โดนหักเข้าระบบ* — the platform-cut sweep (`OAT`, into the company revenue
    /// account). Items are SETTLED JOBS: unlike the other two the file has ONE credit line, and the
    /// items are the ledger behind it rather than a list of recipients. The lifecycle is identical
    /// all the same — an admin still uploads the file by hand and the bank still takes it or does
    /// not.
    Deduction,
}

impl BatchKind {
    /// The typed 409 code for a second void of the same batch.
    const fn already_voided_code(self) -> &'static str {
        match self {
            Self::Payout => "PAYOUT_BATCH_ALREADY_VOIDED",
            Self::Refund => "REFUND_BATCH_ALREADY_VOIDED",
            Self::Deduction => "DEDUCTION_BATCH_ALREADY_VOIDED",
        }
    }

    /// The typed 409 code for acting on a batch whose status admits no further step.
    const fn terminal_code(self) -> &'static str {
        match self {
            Self::Payout => "PAYOUT_BATCH_TERMINAL",
            Self::Refund => "REFUND_BATCH_TERMINAL",
            Self::Deduction => "DEDUCTION_BATCH_TERMINAL",
        }
    }

    /// The typed 409 code for a step the table simply does not allow.
    const fn transition_code(self) -> &'static str {
        match self {
            Self::Payout => "PAYOUT_BATCH_TRANSITION",
            Self::Refund => "REFUND_BATCH_TRANSITION",
            Self::Deduction => "DEDUCTION_BATCH_TRANSITION",
        }
    }

    /// What went back in the queue when this kind of batch is voided, as the admin thinks of it.
    const fn returned_work_th(self) -> &'static str {
        match self {
            Self::Payout => "งานที่อยู่ในไฟล์กลับเข้าคิวรอจ่ายเรียบร้อยแล้ว",
            Self::Refund => "รายการคืนเงินในไฟล์กลับเข้าคิวรอคืนเรียบร้อยแล้ว",
            Self::Deduction => "งานที่อยู่ในไฟล์กลับเข้าคิวรอหักเข้าระบบเรียบร้อยแล้ว",
        }
    }
}

/// The five states a generated export batch can be in — the same five for every stream. Stored as
/// the lowercase `as_str()` text in `payment.payout_batches.status` /
/// `payment.refund_batches.status` (a DB CHECK on each pins the same five values).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BatchStatus {
    /// The file was generated and handed to the admin. Nothing has been sent to the bank yet.
    Generated,
    /// The admin uploaded the file to SCB Business Net.
    Uploaded,
    /// SCB accepted the file — the transfers went out. TERMINAL.
    Confirmed,
    /// SCB refused the file. No money moved; the batch should be voided so the work is payable again.
    Rejected,
    /// Cancelled: every item is un-marked, so its work (a booking to pay, a refund to send) is back
    /// in the payable backlog. TERMINAL.
    Voided,
}

/// The status vocabulary, in lifecycle order — the API's allowed `status` values and the DB CHECK
/// list. Kept next to the enum so the error message can name the whole set without re-typing it.
pub const BATCH_STATUSES: &[&str] = &["generated", "uploaded", "confirmed", "rejected", "voided"];

impl BatchStatus {
    /// The stored/wire form.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Generated => "generated",
            Self::Uploaded => "uploaded",
            Self::Confirmed => "confirmed",
            Self::Rejected => "rejected",
            Self::Voided => "voided",
        }
    }

    /// Parse the stored/wire form. `None` for anything else — the caller decides whether that is a
    /// client 400 (a bad request body) or an internal error (a row the DB CHECK should have refused).
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "generated" => Some(Self::Generated),
            "uploaded" => Some(Self::Uploaded),
            "confirmed" => Some(Self::Confirmed),
            "rejected" => Some(Self::Rejected),
            "voided" => Some(Self::Voided),
            _ => None,
        }
    }

    /// Thai label for the admin-facing messages (the API speaks Thai to admins).
    pub fn label_th(self) -> &'static str {
        match self {
            Self::Generated => "สร้างไฟล์แล้ว",
            Self::Uploaded => "อัปโหลดเข้าธนาคารแล้ว",
            Self::Confirmed => "ธนาคารยืนยันแล้ว",
            Self::Rejected => "ธนาคารปฏิเสธ",
            Self::Voided => "ยกเลิกแล้ว",
        }
    }

    /// A terminal batch admits NO further transition: `Confirmed` because the money already moved
    /// (see the module note), `Voided` because the work is already back in the backlog and a second
    /// void would be a no-op the admin would read as success.
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Confirmed | Self::Voided)
    }
}

/// THE TRANSITION TABLE. `true` iff `from → to` is a step the lifecycle allows.
///
/// A same-status "transition" is deliberately NOT allowed: re-marking an uploaded batch uploaded
/// tells the admin nothing changed while looking like it did, and for `voided → voided` it would
/// hide a double-void (which the admin genuinely needs to know about — the first void already
/// returned the bookings to the backlog, and a second one may mean they are looking at a stale page).
pub fn is_legal(from: BatchStatus, to: BatchStatus) -> bool {
    use BatchStatus::*;
    matches!(
        (from, to),
        (Generated, Uploaded)
            | (Uploaded, Confirmed)
            | (Uploaded, Rejected)
            | (Generated | Uploaded | Rejected, Voided)
    )
}

/// Apply the table, turning an illegal step into the typed Thai 409 the API returns. `kind` picks
/// the stream's error codes + noun; the legality itself is stream-independent.
///
/// The double-void case gets its OWN code because it is the one an admin hits by accident (two tabs,
/// a re-submitted form) and the UI wants to say something specific and reassuring: the batch is
/// already cancelled and the work is already back in the queue.
pub fn check_transition(
    kind: BatchKind,
    from: BatchStatus,
    to: BatchStatus,
) -> Result<(), AppError> {
    if is_legal(from, to) {
        return Ok(());
    }
    if from == BatchStatus::Voided && to == BatchStatus::Voided {
        return Err(AppError::ConflictCode {
            code: kind.already_voided_code(),
            message: format!("ไฟล์นี้ถูกยกเลิกไปแล้ว — {}", kind.returned_work_th()),
        });
    }
    if from.is_terminal() {
        return Err(AppError::ConflictCode {
            code: kind.terminal_code(),
            message: format!(
                "ไฟล์นี้อยู่ในสถานะ “{}” ซึ่งเปลี่ยนต่อไม่ได้แล้ว (ถ้าโอนผิดต้องทำรายการโอนแก้ใหม่ ไม่ใช่ยกเลิกไฟล์เดิม)",
                from.label_th()
            ),
        });
    }
    Err(AppError::ConflictCode {
        code: kind.transition_code(),
        message: format!(
            "เปลี่ยนสถานะจาก “{}” เป็น “{}” ไม่ได้",
            from.label_th(),
            to.label_th()
        ),
    })
}

#[cfg(test)]
mod tests {
    use super::BatchStatus::*;
    use super::*;

    /// EVERY legal transition, spelled out — this list IS the lifecycle contract.
    #[test]
    fn the_legal_transitions_are_exactly_these() {
        for (from, to) in [
            (Generated, Uploaded),
            (Uploaded, Confirmed),
            (Uploaded, Rejected),
            (Generated, Voided),
            (Uploaded, Voided),
            (Rejected, Voided),
        ] {
            assert!(is_legal(from, to), "{from:?} → {to:?} must be legal");
            assert!(check_transition(BatchKind::Payout, from, to).is_ok());
        }
    }

    /// EVERY other pair is illegal. Written as "all pairs minus the legal ones" so a transition
    /// added to the table without a test can never slip through unnoticed.
    #[test]
    fn every_other_pair_is_refused() {
        let all = [Generated, Uploaded, Confirmed, Rejected, Voided];
        let legal = [
            (Generated, Uploaded),
            (Uploaded, Confirmed),
            (Uploaded, Rejected),
            (Generated, Voided),
            (Uploaded, Voided),
            (Rejected, Voided),
        ];
        for from in all {
            for to in all {
                if legal.contains(&(from, to)) {
                    continue;
                }
                assert!(!is_legal(from, to), "{from:?} → {to:?} must NOT be legal");
                assert!(
                    matches!(
                        check_transition(BatchKind::Payout, from, to),
                        Err(AppError::ConflictCode { .. })
                    ),
                    "{from:?} → {to:?} must be a typed 409"
                );
            }
        }
    }

    #[test]
    fn a_confirmed_batch_can_never_be_voided() {
        // The money already left the account: voiding would un-mark the bookings and the next run
        // would pay those guards a SECOND time for the same jobs.
        let err = check_transition(BatchKind::Payout, Confirmed, Voided)
            .expect_err("confirmed is terminal");
        let AppError::ConflictCode { code, message } = err else {
            unreachable!("a lifecycle refusal is a typed conflict")
        };
        assert_eq!(code, "PAYOUT_BATCH_TERMINAL");
        assert!(
            message.contains("ธนาคารยืนยันแล้ว"),
            "names the state: {message}"
        );
        // …and nothing else can follow it either.
        for to in [Generated, Uploaded, Rejected, Confirmed] {
            assert!(check_transition(BatchKind::Payout, Confirmed, to).is_err());
        }
    }

    #[test]
    fn a_double_void_is_its_own_code_not_a_silent_no_op() {
        let err = check_transition(BatchKind::Payout, Voided, Voided).expect_err("already voided");
        let AppError::ConflictCode { code, .. } = err else {
            unreachable!()
        };
        assert_eq!(code, "PAYOUT_BATCH_ALREADY_VOIDED");
    }

    #[test]
    fn a_rejected_batch_is_not_terminal_and_can_be_voided() {
        // The bank refused the file, so no money moved — voiding is exactly what must happen next
        // so those jobs become payable again.
        assert!(!Rejected.is_terminal());
        assert!(check_transition(BatchKind::Payout, Rejected, Voided).is_ok());
        // …but it cannot jump back to uploaded/confirmed: that file is spent, a new one is generated.
        assert!(check_transition(BatchKind::Payout, Rejected, Uploaded).is_err());
        assert!(check_transition(BatchKind::Payout, Rejected, Confirmed).is_err());
    }

    #[test]
    fn a_status_never_transitions_to_itself() {
        for s in [Generated, Uploaded, Confirmed, Rejected, Voided] {
            assert!(
                check_transition(BatchKind::Payout, s, s).is_err(),
                "{s:?} → {s:?}"
            );
        }
    }

    #[test]
    fn the_wire_form_round_trips_and_matches_the_db_check_list() {
        for name in BATCH_STATUSES {
            let parsed = BatchStatus::parse(name).expect("every listed status parses");
            assert_eq!(parsed.as_str(), *name);
        }
        assert_eq!(BATCH_STATUSES.len(), 5);
        assert_eq!(BatchStatus::parse("Uploaded"), None, "case-sensitive");
        assert_eq!(BatchStatus::parse("cancelled"), None);
        assert_eq!(BatchStatus::parse(""), None);
    }

    #[test]
    fn only_confirmed_and_voided_are_terminal() {
        assert!(Confirmed.is_terminal() && Voided.is_terminal());
        for s in [Generated, Uploaded, Rejected] {
            assert!(!s.is_terminal(), "{s:?} still has somewhere to go");
        }
    }

    /// The OTHER TWO streams walk the identical table but report their own codes. Both halves
    /// matter: the payout's published codes must not shift under the admin panel, and a refund or
    /// sweep screen must not have to recognise `PAYOUT_…` to tell "already cancelled" from "cannot
    /// be re-opened".
    #[test]
    fn every_stream_shares_the_table_but_not_the_codes() {
        for kind in [BatchKind::Refund, BatchKind::Deduction] {
            for (from, to) in [
                (Generated, Uploaded),
                (Uploaded, Confirmed),
                (Rejected, Voided),
            ] {
                assert!(check_transition(kind, from, to).is_ok(), "{kind:?}");
            }
            // …and `confirmed` is terminal for every stream: the bank took the file, so un-marking
            // its items would pay/refund/sweep the same money twice.
            assert!(
                check_transition(kind, Confirmed, Voided).is_err(),
                "{kind:?}"
            );
        }
        let codes = |kind| {
            [
                check_transition(kind, Voided, Voided),
                check_transition(kind, Confirmed, Voided),
                check_transition(kind, Generated, Confirmed),
            ]
            .map(|e| match e {
                Err(AppError::ConflictCode { code, .. }) => code,
                other => unreachable!("expected a typed conflict, got {other:?}"),
            })
        };
        assert_eq!(
            codes(BatchKind::Payout),
            [
                "PAYOUT_BATCH_ALREADY_VOIDED",
                "PAYOUT_BATCH_TERMINAL",
                "PAYOUT_BATCH_TRANSITION"
            ],
            "the payout's codes are a published contract and must not move"
        );
        assert_eq!(
            codes(BatchKind::Refund),
            [
                "REFUND_BATCH_ALREADY_VOIDED",
                "REFUND_BATCH_TERMINAL",
                "REFUND_BATCH_TRANSITION"
            ]
        );
        assert_eq!(
            codes(BatchKind::Deduction),
            [
                "DEDUCTION_BATCH_ALREADY_VOIDED",
                "DEDUCTION_BATCH_TERMINAL",
                "DEDUCTION_BATCH_TRANSITION"
            ]
        );
        // …and the Thai copy names what actually went back in the queue for that stream — a refund
        // screen saying "งานกลับเข้าคิวรอจ่าย" would be describing someone else's money.
        let wording = |kind| match check_transition(kind, Voided, Voided) {
            Err(AppError::ConflictCode { message, .. }) => message,
            other => unreachable!("expected a typed conflict, got {other:?}"),
        };
        assert!(wording(BatchKind::Refund).contains("คืนเงิน"));
        assert!(wording(BatchKind::Deduction).contains("หักเข้าระบบ"));
        assert!(wording(BatchKind::Payout).contains("รอจ่าย"));
    }
}
