//! Cross-service domain enums + the standard API response envelope. Ported from v1.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, sqlx::Type, ToSchema)]
#[sqlx(type_name = "user_role", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum UserRole {
    Admin,
    Customer,
    Guard,
}

impl std::fmt::Display for UserRole {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UserRole::Admin => write!(f, "admin"),
            UserRole::Customer => write!(f, "customer"),
            UserRole::Guard => write!(f, "guard"),
        }
    }
}

impl std::str::FromStr for UserRole {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "admin" => Ok(UserRole::Admin),
            "customer" => Ok(UserRole::Customer),
            "guard" => Ok(UserRole::Guard),
            other => Err(format!("Unknown role: {other}")),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, sqlx::Type, ToSchema)]
#[sqlx(type_name = "approval_status", rename_all = "lowercase")]
#[serde(rename_all = "lowercase")]
pub enum ApprovalStatus {
    Pending,
    Approved,
    Rejected,
}

impl std::fmt::Display for ApprovalStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApprovalStatus::Pending => write!(f, "pending"),
            ApprovalStatus::Approved => write!(f, "approved"),
            ApprovalStatus::Rejected => write!(f, "rejected"),
        }
    }
}

impl std::str::FromStr for ApprovalStatus {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "pending" => Ok(ApprovalStatus::Pending),
            "approved" => Ok(ApprovalStatus::Approved),
            "rejected" => Ok(ApprovalStatus::Rejected),
            other => Err(format!("Unknown approval status: {other}")),
        }
    }
}

/// Standard success envelope: `{ "success": true, "data": ... }`.
/// Errors use [`crate::error::ErrorBody`] instead.
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl<T: Serialize> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            success: true,
            data: Some(data),
            error: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn user_role_display_lowercase() {
        assert_eq!(UserRole::Admin.to_string(), "admin");
        assert_eq!(UserRole::Customer.to_string(), "customer");
        assert_eq!(UserRole::Guard.to_string(), "guard");
    }

    #[test]
    fn user_role_from_str_case_insensitive() {
        assert_eq!("Admin".parse::<UserRole>().unwrap(), UserRole::Admin);
        assert_eq!("CUSTOMER".parse::<UserRole>().unwrap(), UserRole::Customer);
        assert_eq!("guard".parse::<UserRole>().unwrap(), UserRole::Guard);
    }

    #[test]
    fn user_role_from_str_rejects_unknown() {
        assert!("manager".parse::<UserRole>().is_err());
        assert!("".parse::<UserRole>().is_err());
    }

    #[test]
    fn user_role_roundtrip_display_parse() {
        for role in [UserRole::Admin, UserRole::Customer, UserRole::Guard] {
            let parsed: UserRole = role.to_string().parse().unwrap();
            assert_eq!(parsed, role);
        }
    }

    #[test]
    fn api_response_success_has_correct_fields() {
        let resp = ApiResponse::success("hello");
        assert!(resp.success);
        assert_eq!(resp.data, Some("hello"));
        assert!(resp.error.is_none());
    }

    #[test]
    fn api_response_success_serializes_without_error_field() {
        let resp = ApiResponse::success(42);
        let json = serde_json::to_value(&resp).unwrap();
        assert_eq!(json["success"], true);
        assert_eq!(json["data"], 42);
        assert!(json.get("error").is_none());
    }
}
