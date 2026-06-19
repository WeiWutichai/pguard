-- Guard profile avatar (self-uploaded profile picture). One private S3 object key per guard,
-- written post-approval by the logged-in guard (own-only) via POST /profile/guard/{id}/avatar and
-- read (owner-or-admin) as a short-lived presigned URL. Only the key + metadata live here; the
-- image bytes stay in S3 (CLAUDE.md Data). Mirrors the credential `*_key` columns (0001).
ALTER TABLE profile.guard_profiles
    ADD COLUMN IF NOT EXISTS avatar_key TEXT;
