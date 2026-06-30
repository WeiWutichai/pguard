//! Payment-provider config — the feature flag that selects the SIMULATED vs the REAL (Slip2Go)
//! money path, plus the Slip2Go + receiving-account settings. Pure env parsing (no I/O).
//!
//! The service ALWAYS starts (so nothing breaks until the slip path is flipped on): when
//! `PAYMENT_PROVIDER=simulated` (the default), the Slip2Go secret / receiving account are NOT
//! required. They are only enforced when `PAYMENT_PROVIDER=slip2go` — fail-fast at startup so a
//! misconfigured real path never silently degrades.

use shared::error::AppError;

/// Which money path the service serves.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaymentProvider {
    /// The SIMULATED gateway (default): `POST /payments` auto-marks the estimate paid (`prepaid`).
    /// `POST /payments/{id}/slip` is rejected (the slip path is off).
    Simulated,
    /// The REAL path: payment is stamped paid only by a Slip2Go-verified slip
    /// (`POST /payments/{id}/slip`). The simulated auto-mark `POST /payments` is rejected.
    Slip2Go,
}

impl PaymentProvider {
    /// Parse `PAYMENT_PROVIDER` (`simulated` | `slip2go`, case/space-insensitive). Unset or any
    /// unrecognized value → `Simulated` (the safe default — nothing breaks until explicitly
    /// flipped). Pure.
    pub fn from_env_value(val: Option<&str>) -> Self {
        match val.map(|s| s.trim().to_ascii_lowercase()).as_deref() {
            Some("slip2go") => Self::Slip2Go,
            _ => Self::Simulated,
        }
    }

    pub fn is_slip2go(self) -> bool {
        matches!(self, Self::Slip2Go)
    }
}

/// Slip-path config: the provider flag + the receiving account number the slip's receiver must
/// match. `receiving_account` is required only under `Slip2Go` (validated at construction).
#[derive(Debug, Clone)]
pub struct SlipPaymentConfig {
    pub provider: PaymentProvider,
    /// OUR PromptPay/bank account number — every accepted slip's receiver must equal this
    /// (anti-fraud: reject slips paid to any other account). Empty under `Simulated`.
    pub receiving_account: String,
}

impl SlipPaymentConfig {
    /// Read `PAYMENT_PROVIDER` + `RECEIVING_ACCOUNT` from the environment. Under `slip2go`,
    /// `RECEIVING_ACCOUNT` is required (fail-fast); under `simulated` it is ignored.
    pub fn from_env() -> Result<Self, AppError> {
        let provider =
            PaymentProvider::from_env_value(std::env::var("PAYMENT_PROVIDER").ok().as_deref());
        let receiving_account = std::env::var("RECEIVING_ACCOUNT")
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_default();
        if provider.is_slip2go() && receiving_account.is_empty() {
            return Err(AppError::Internal(
                "RECEIVING_ACCOUNT is required when PAYMENT_PROVIDER=slip2go".to_string(),
            ));
        }
        Ok(Self {
            provider,
            receiving_account,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_defaults_to_simulated() {
        assert_eq!(
            PaymentProvider::from_env_value(None),
            PaymentProvider::Simulated
        );
        assert_eq!(
            PaymentProvider::from_env_value(Some("")),
            PaymentProvider::Simulated
        );
        assert_eq!(
            PaymentProvider::from_env_value(Some("bogus")),
            PaymentProvider::Simulated
        );
        assert_eq!(
            PaymentProvider::from_env_value(Some("simulated")),
            PaymentProvider::Simulated
        );
    }

    #[test]
    fn provider_parses_slip2go_case_insensitively() {
        assert_eq!(
            PaymentProvider::from_env_value(Some("slip2go")),
            PaymentProvider::Slip2Go
        );
        assert_eq!(
            PaymentProvider::from_env_value(Some("  SLIP2GO ")),
            PaymentProvider::Slip2Go
        );
    }
}
