//! PURE opaque-refresh-token format helpers.
//!
//! A refresh token is `"{rotation_id}.{secret}"`: the `rotation_id` (a UUID) is the
//! public lookup key, the `secret` (random) is Argon2-verified against the stored hash.
//! Splitting/assembling the two halves is pure string + UUID work, kept here so the
//! transport/repo layers stay thin and the parse is unit-tested.

use uuid::Uuid;

/// Assemble the opaque token a client receives from its two parts.
pub fn assemble(rotation_id: Uuid, secret: &str) -> String {
    format!("{rotation_id}.{secret}")
}

/// Parse a presented refresh token into `(rotation_id, secret)`. Returns `None` for any
/// malformed input (missing separator, bad UUID, empty secret) — the caller maps that to
/// a generic 401, never leaking which half was wrong.
pub fn parse(token: &str) -> Option<(Uuid, &str)> {
    let (id_part, secret) = token.split_once('.')?;
    if secret.is_empty() {
        return None;
    }
    let rotation_id = Uuid::parse_str(id_part).ok()?;
    Some((rotation_id, secret))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assemble_then_parse_roundtrips() {
        let id = Uuid::new_v4();
        let token = assemble(id, "the-secret-half");
        let (parsed_id, secret) = parse(&token).unwrap();
        assert_eq!(parsed_id, id);
        assert_eq!(secret, "the-secret-half");
    }

    #[test]
    fn parse_rejects_missing_separator() {
        assert!(parse("no-dot-here").is_none());
    }

    #[test]
    fn parse_rejects_bad_rotation_uuid() {
        assert!(parse("not-a-uuid.secret").is_none());
    }

    #[test]
    fn parse_rejects_empty_secret() {
        let id = Uuid::new_v4();
        assert!(parse(&format!("{id}.")).is_none());
    }

    #[test]
    fn parse_keeps_dots_inside_secret() {
        // Only the FIRST dot splits; secrets may (in principle) contain dots.
        let id = Uuid::new_v4();
        let token = format!("{id}.a.b.c");
        let (parsed_id, secret) = parse(&token).unwrap();
        assert_eq!(parsed_id, id);
        assert_eq!(secret, "a.b.c");
    }
}
