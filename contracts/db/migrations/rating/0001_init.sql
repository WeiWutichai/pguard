-- pguard rating-service — schema init (Phase 3: split from v1 booking god-service).
--
-- Reviews of guards by customers after a completed job + admin visibility moderation + the
-- rating summary other services (booking's available-guards) consume for discovery.
--
-- Per-service schema ownership: ONLY rating-service writes to schema `rating` (CLAUDE.md
-- "Data"). NO cross-service foreign keys — `guard_id`, `customer_id`, `assignment_id`
-- (= the booking id) are bare UUIDs owned by identity/booking; integrity across boundaries
-- is maintained via the service-JWT'd internal read + events, never FKs.
--
-- Ported from v1 `reviews.guard_reviews` (migrations 014 + 035), with v2 changes:
--   - ratings are INTEGER 1..=5 (v1 used DECIMAL(2,1); v2 spec is whole-star 1–5).
--   - no cross-schema FKs to auth.users / booking.assignments.
--   - `is_visible` (admin moderation) baked in from the start (v1 added it in 035).
--
-- Note on indexes: created inline because the table is empty at creation. LATER additive
-- indexes on populated tables must use CREATE INDEX CONCURRENTLY (CLAUDE.md "Data").

CREATE SCHEMA IF NOT EXISTS rating;

CREATE TABLE rating.guard_reviews (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guard_id        UUID        NOT NULL,            -- the reviewed guard (owned by identity, no FK)
    customer_id     UUID        NOT NULL,            -- the reviewing customer (owned by identity, no FK)
    assignment_id   UUID        NOT NULL,            -- = the booking id (owned by booking, no FK)

    -- Overall is required; category ratings are optional. Whole-star 1..=5.
    overall_rating  SMALLINT    NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),
    punctuality     SMALLINT    CHECK (punctuality     BETWEEN 1 AND 5),
    professionalism SMALLINT    CHECK (professionalism BETWEEN 1 AND 5),
    communication   SMALLINT    CHECK (communication   BETWEEN 1 AND 5),
    appearance      SMALLINT    CHECK (appearance      BETWEEN 1 AND 5),

    review_text     TEXT        CHECK (review_text IS NULL OR char_length(review_text) <= 2000),

    -- Admin moderation: hidden reviews never surface on public discovery (default visible).
    is_visible      BOOLEAN     NOT NULL DEFAULT true,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One review per assignment (a retried/duplicate submit → 409).
    UNIQUE (assignment_id)
);

-- Hot path: a guard's visible reviews + summary (public discovery), newest first.
CREATE INDEX idx_guard_reviews_guard ON rating.guard_reviews (guard_id, created_at DESC);
-- Public discovery + summary filter on visibility.
CREATE INDEX idx_guard_reviews_visible ON rating.guard_reviews (guard_id) WHERE is_visible = true;

-- Transactional outbox: the review row AND the `rating.submitted` event row are written in
-- ONE transaction (CLAUDE.md "Cross-tx consistency"); a background relay publishes to NATS
-- (subject = topic) so notification consumes it. `payload` is a fully-formed EventEnvelope.
CREATE TABLE rating.outbox (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic        TEXT        NOT NULL,            -- = EventEnvelope.event_type (NATS subject)
    payload      JSONB       NOT NULL,            -- the serialized EventEnvelope
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

-- Relay polls only unpublished rows, oldest first.
CREATE INDEX idx_rating_outbox_unpublished
    ON rating.outbox (created_at)
    WHERE published_at IS NULL;
