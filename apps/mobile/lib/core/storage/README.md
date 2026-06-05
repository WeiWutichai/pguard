<!-- pguard v2 scaffold stub. See ../../../../CLAUDE.md "Flutter (mobile)". -->

# core/storage

**Secrets in `FlutterSecureStorage`; non-sensitive prefs in `SharedPreferences`.**

Per CLAUDE.md ("Flutter (mobile)" Do/Don't):

- `FlutterSecureStorage` ONLY for sensitive values:
  - access / refresh tokens
  - PIN hash
- `SharedPreferences` ONLY for non-sensitive prefs:
  - locale (TH/EN), theme, onboarding-seen flags, last-used filters
- **Never** store tokens or the PIN hash in `SharedPreferences`.

## TODO

- [ ] `SecureTokenStore` (read/write/clear access + refresh tokens, PIN hash).
- [ ] `PrefsStore` (locale + UI prefs).
- [ ] Wipe-on-logout helper that clears the secure store.
