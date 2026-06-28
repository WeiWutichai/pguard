"use client";

// Client-side SHA-256 PIN hashing for the identity password contracts (#144 change-password).
// The identity service Argon2's whatever it receives; the OpenAPI source of truth mandates that
// `pin_hash` / `new_pin_hash` / `current_password` are the LOWERCASE-HEX SHA-256 of the user's PIN
// (exactly 64 hex chars — `registration::validate_pin_hash`). We hash here so the raw PIN never
// leaves the browser in plaintext and so the wire shape matches register/login.
//
// Uses the Web Crypto SubtleCrypto digest (available in every modern browser; this module is
// client-only). No dependency added.

/** SHA-256 a UTF-8 string into the 64-char lowercase-hex digest the identity contract expects. */
export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
