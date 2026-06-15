-- pguard booking-service — admin-managed service catalog (pricing).
--
-- An admin-curated catalog of bookable service types with a base rate. STANDALONE for now:
-- the charge path is NOT rewired to read from here — bookings keep their server-owned
-- `base_fee` (see migration 0002). This catalog is the admin surface (web-admin "Pricing"),
-- prepared ahead of a future "booking reads its base_fee from the catalog" integration. That
-- integration is a deliberate, separate decision (it touches the money path) and is out of
-- scope here — so adding this table changes no existing behaviour.
--
-- Per-service schema ownership: only booking-service writes schema `booking` (CLAUDE.md).
-- Index created inline (the table is empty at creation); later additive indexes on a
-- populated table must use CREATE INDEX CONCURRENTLY in their own migration.

CREATE TABLE booking.service_catalog (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name_th     TEXT          NOT NULL,
    name_en     TEXT          NOT NULL,
    base_fee    NUMERIC(12,2) NOT NULL CHECK (base_fee >= 0),       -- ฿ per hour per guard
    min_hours   INT           NOT NULL DEFAULT 1 CHECK (min_hours >= 1 AND min_hours <= 24),
    notes       TEXT,
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Admin list orders active-first then newest; the partial-friendly composite covers it.
CREATE INDEX idx_service_catalog_active ON booking.service_catalog (is_active, created_at DESC);
