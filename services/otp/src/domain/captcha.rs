//! Math-captcha generation — PURE. The randomness source is injected from the caller
//! (the API layer uses `rand::thread_rng()`), keeping this function deterministic and
//! unit-testable. Ported from v1 `create_otp_challenge`
//! (`../guard-dispatch/services/auth/src/service.rs`).

/// A freshly minted captcha: the human-facing `question`, plus the `answer` the API
/// layer stores in Redis (`otp_captcha:{id}`) for GETDEL verification on `/otp/request`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptchaChallenge {
    pub question: String,
    pub answer: u32,
}

/// Which arithmetic operation a captcha uses. Supplied by the caller (RNG stays out of this pure
/// core). Both operations keep the challenge to TWO operands and a NON-NEGATIVE integer answer, so
/// the accessibility target (elderly users) is unchanged while the answer space and pattern widen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CaptchaOp {
    Add,
    Sub,
}

/// Generate a two-operand arithmetic captcha from operands `a`, `b` and operation `op`.
///
/// STRENGTHENED (deep-review LOW #37): the previous form was ALWAYS `"{a} + {b} = ?"` with both
/// operands drawn from `1..20` — a fixed pattern with a ~37-value answer space that a one-line
/// script (`parse the two ints, add`) solved for free. Mixing in subtraction and letting the caller
/// widen the operand range breaks that fixed pattern and enlarges the answer space, WITHOUT breaking
/// the client contract (the response is still `{question, answer}`; the app just renders `question`
/// and posts the typed integer, compared by string-equality on `/otp/request`) and WITHOUT hurting
/// accessibility (still two operands, still a non-negative whole-number answer — for `Sub` the
/// operands are ordered so `larger - smaller` never goes negative).
///
/// NOTE / DESIGN LIMITATION: a math captcha is inherently machine-solvable, so this remains a UX /
/// casual-bot barrier, NOT a real anti-automation control. The actual SMS-cost-abuse defense is a
/// server-side send budget independent of the per-phone caps (the broader deep-review #37
/// recommendation) — a larger feature than a pure-captcha change and out of scope here.
pub fn generate_captcha(a: u32, b: u32, op: CaptchaOp) -> CaptchaChallenge {
    match op {
        CaptchaOp::Add => CaptchaChallenge {
            question: format!("{a} + {b} = ?"),
            answer: a + b,
        },
        CaptchaOp::Sub => {
            // Order operands so the answer is a non-negative integer regardless of how the caller
            // drew them (no negatives for the user to reason about).
            let (hi, lo) = if a >= b { (a, b) } else { (b, a) };
            CaptchaChallenge {
                question: format!("{hi} - {lo} = ?"),
                answer: hi - lo,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addition_question_and_answer_are_consistent() {
        let c = generate_captcha(7, 5, CaptchaOp::Add);
        assert_eq!(c.question, "7 + 5 = ?");
        assert_eq!(c.answer, 12);
    }

    #[test]
    fn addition_answer_is_the_sum() {
        let c = generate_captcha(19, 19, CaptchaOp::Add);
        assert_eq!(c.answer, 38);
        assert!(c.question.contains("19 + 19"));
    }

    #[test]
    fn subtraction_orders_operands_for_a_non_negative_answer() {
        // Larger-first: straightforward.
        let c = generate_captcha(42, 17, CaptchaOp::Sub);
        assert_eq!(c.question, "42 - 17 = ?");
        assert_eq!(c.answer, 25);
        // Smaller-first: operands are reordered so the answer never underflows.
        let c = generate_captcha(17, 42, CaptchaOp::Sub);
        assert_eq!(c.question, "42 - 17 = ?");
        assert_eq!(c.answer, 25);
        // Equal operands → zero, never a panic.
        let c = generate_captcha(30, 30, CaptchaOp::Sub);
        assert_eq!(c.answer, 0);
    }
}
