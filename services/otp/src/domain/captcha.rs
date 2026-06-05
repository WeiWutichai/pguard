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

/// Generate an addition captcha from two operands. Only addition is used — simple
/// enough for elderly users, still a bot barrier (v1 rationale). Operands are supplied
/// by the caller so the pure core has no RNG dependency.
pub fn generate_captcha(a: u32, b: u32) -> CaptchaChallenge {
    CaptchaChallenge {
        question: format!("{a} + {b} = ?"),
        answer: a + b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captcha_question_and_answer_are_consistent() {
        let c = generate_captcha(7, 5);
        assert_eq!(c.question, "7 + 5 = ?");
        assert_eq!(c.answer, 12);
    }

    #[test]
    fn captcha_answer_is_the_sum() {
        let c = generate_captcha(19, 19);
        assert_eq!(c.answer, 38);
        assert!(c.question.contains("19 + 19"));
    }
}
