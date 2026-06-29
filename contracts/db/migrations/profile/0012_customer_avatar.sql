-- Customer profile avatar (self-uploaded profile picture). The MIRROR of guard_profiles.avatar_key
-- (0008) for the customer side. One private S3 object key per customer, written own-only by the
-- logged-in customer via POST /profile/customer/{id}/avatar and read (owner-or-admin, or the
-- assigned guard via GET /customers/{id}/public) as a short-lived presigned URL. Only the key +
-- metadata live here; the image bytes stay in S3 (CLAUDE.md Data). Mirrors the guard avatar column.
ALTER TABLE profile.customer_profiles
    ADD COLUMN IF NOT EXISTS avatar_key TEXT;
