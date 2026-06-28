-- pguard booking-service — link a booking to the service-catalog entry it was booked against
-- (the SERVICE_TYPE dimension for the admin "งานตามประเภทบริการ" / Bookings-by-service report, #140).
--
-- Background: migration 0005 added booking.service_catalog (admin-managed pricing). At create,
-- the booking handler already RESOLVES a customer-picked `service_id` to a server-owned `base_fee`
-- (CLAUDE.md money rules) — but it then DISCARDED the id, so no booking recorded WHICH service it
-- was, leaving the by-service report with no dimension to group on. This adds that missing link.
--
-- `service_id` is NULLABLE: it is null for back-compat bookings created without picking a catalog
-- service (the base_fee-default path), so the report keeps an honest "unspecified" bucket rather
-- than dropping those jobs. The mobile booking flow ALREADY sends `service_id` when a service is
-- chosen (apps/mobile booking_flow_controller.dart), so new app bookings are typed immediately —
-- no mobile change is required to populate this.
--
-- Same-schema reference: service_catalog lives in schema `booking` too, so a FK here does NOT
-- cross a service boundary (CLAUDE.md forbids only CROSS-service FKs). ON DELETE SET NULL keeps the
-- catalog soft-deletable (deactivate, never hard-delete) without orphaning a booking; a hard delete
-- would simply re-bucket the booking as "unspecified". `NOT VALID` is unnecessary on an empty table.
--
-- Dev note: booking.bookings is empty (no production users — strangler-fig is discipline-only here;
-- see 0002/0006), so ADD COLUMN nullable + an inline CREATE INDEX is a safe, instant change. On a
-- POPULATED production table this would split: add nullable column → backfill → add the FK as
-- NOT VALID then VALIDATE, and build the index with CREATE INDEX CONCURRENTLY (CLAUDE.md "Data") in
-- its own non-transactional migration.

ALTER TABLE booking.bookings
    ADD COLUMN service_id UUID
        REFERENCES booking.service_catalog (id) ON DELETE SET NULL;  -- null = no catalog service picked

-- The by-service report groups Σ(count) + Σ(revenue) per service_id over a created_at window. This
-- partial index covers the grouping scan for the typed bookings (the NULL "unspecified" bucket is
-- aggregated separately and needs no index). created_at is included so the windowed report can scan
-- the (service, time) range without touching unrelated rows.
CREATE INDEX idx_bookings_service_id
    ON booking.bookings (service_id, created_at)
    WHERE service_id IS NOT NULL;
