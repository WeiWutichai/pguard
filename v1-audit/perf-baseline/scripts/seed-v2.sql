-- ============================================================================
-- pguard v2 perf-baseline seed  (Phase 0.5 · B1 — v2 per-service schemas)
--
-- Rewrites the v1 seed (auth.*/tracking.* + booking.service_rates/guard_requests)
-- for the MERGED v2 migrations: identity.* / profile.* / presence.* / booking.* /
-- chat.* / rating.* — column names taken from contracts/db/migrations/<svc>/*.sql.
--
-- Idempotent (ON CONFLICT DO NOTHING) — safe to re-run. Deterministic UUIDs.
-- Apply to the PRIMARY after migrations; the replica streams it over WAL:
--   docker compose -f infra/docker/docker-compose.prod.yml exec -T postgres \
--     psql -U pguard -d pguard < v1-audit/perf-baseline/scripts/seed-v2.sql
--
-- Creates:
--   • 1 customer (phone 0820000001) + 1 test guard (0810000001) + 200 approved guards
--   • 200 guards ONLINE in presence.guard_locations, GPS within ~22 km of 13.7563,100.5018
--   • 100 booking.bookings owned by the customer, status='accepted' (payable: payment
--     create requires `accepted`), base_fee 500 × 4h × 1 guard ⇒ expected_total 2000
--   • 100 chat.conversations (+participants: customer & guard, +1 guard message each) for the
--     N+1 list_conversations read
--   • rating.guard_reviews for the first 50 guards (3 each) for the ratings-summary read
--
-- All accounts log in with password:  Password123!
-- (password_hash below is an Argon2id PHC string of that exact string — the argon2 verifier
--  reads the cost params from the PHC, so it verifies regardless of the service's own config.)
--
-- v2 DIVERGENCES from the v1-shaped spec (built to the REAL schema):
--   • NO booking.service_rates / booking.guard_requests — v2 has booking.bookings with the
--     pricing columns (base_fee/guard_count/tip) on the row.
--   • identity.users has NO full_name; presence uses lat/lng (+NOT NULL recorded_at); chat uses
--     `participants` (with user_role) not `conversation_participants`.
-- ============================================================================

\set ON_ERROR_STOP on
\set pwhash '$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU'

-- ---- admin (for the C5.3 admin-list gate: GET /v1/admin/guard-profiles) ---------
INSERT INTO identity.users (id, phone, email, password_hash, role, approval_status, is_active)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '0800000001', 'k6admin@t.local', :'pwhash', 'admin', 'approved', true)
ON CONFLICT DO NOTHING;

-- ---- test customer -------------------------------------------------------------
INSERT INTO identity.users (id, phone, email, password_hash, role, approval_status, is_active)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', '0820000001', 'k6cust@t.local', :'pwhash', 'customer', 'approved', true)
ON CONFLICT DO NOTHING;

INSERT INTO profile.customer_profiles (user_id, full_name, address)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'K6 Customer', '123 Sukhumvit Rd, Bangkok 10110')
ON CONFLICT (user_id) DO NOTHING;

-- ---- test guard (used by gps-websocket.js) -------------------------------------
INSERT INTO identity.users (id, phone, email, password_hash, role, approval_status, is_active)
VALUES ('99999999-9999-9999-9999-999999999999', '0810000001', 'k6guard0@t.local', :'pwhash', 'guard', 'approved', true)
ON CONFLICT DO NOTHING;
INSERT INTO profile.guard_profiles (user_id, years_of_experience, gender, bank_name, account_number, account_name, approval_status)
VALUES ('99999999-9999-9999-9999-999999999999', 3, 'male', 'KBank', '0000000000', 'K6 Guard 0', 'approved')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO presence.guard_locations (guard_id, lat, lng, is_online, recorded_at)
VALUES ('99999999-9999-9999-9999-999999999999', 13.7563, 100.5018, true, now())
ON CONFLICT (guard_id) DO NOTHING;

-- ---- 200 approved, online guards within ~22 km ---------------------------------
INSERT INTO identity.users (id, phone, email, password_hash, role, approval_status, is_active)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       '0831' || lpad(g::text, 6, '0'),
       'k6guard' || g || '@t.local',
       :'pwhash', 'guard', 'approved', true
FROM generate_series(1, 200) AS g
ON CONFLICT DO NOTHING;

INSERT INTO profile.guard_profiles (user_id, years_of_experience, gender, bank_name, account_number, account_name, approval_status)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       (g % 10) + 1, 'male', 'KBank', lpad(g::text, 10, '0'), 'K6 Guard ' || g, 'approved'
FROM generate_series(1, 200) AS g
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO presence.guard_locations (guard_id, lat, lng, is_online, recorded_at)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       13.7563  + (random() - 0.5) * 0.4,   -- ±0.2° lat ≈ ±22 km
       100.5018 + (random() - 0.5) * 0.4,   -- ±0.2° lng ≈ ±22 km
       true, now()
FROM generate_series(1, 200) AS g
ON CONFLICT (guard_id) DO NOTHING;

-- ---- 100 bookings owned by the customer, status='accepted' (payable pool) -------
-- expected_total = base_fee(500) × hours(4) × guard_count(1) + tip(0) = 2000 (payment-create.js
-- sends amount ≥ this). guard_id round-robins the 200 guards.
INSERT INTO booking.bookings
       (id, customer_id, guard_id, status, address, scheduled_at, hours, base_fee, guard_count, tip)
SELECT ('11111111-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       'cccccccc-cccc-cccc-cccc-cccccccccccc',
       ('99999999-0000-0000-0000-' || lpad(to_hex(((i - 1) % 200) + 1), 12, '0'))::uuid,
       'accepted', 'Seed site #' || i, now() + interval '1 day', 4, 500.00, 1, 0
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- ---- 100 conversations (customer + a guard) + 1 guard message each --------------
INSERT INTO chat.conversations (id, request_id, request_status)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('11111111-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid, 'accepted'
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- participant: customer (role drives the N+1 list's per-role unread + counterpart pick)
INSERT INTO chat.participants (conversation_id, user_id, user_role, display_name)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       'cccccccc-cccc-cccc-cccc-cccccccccccc', 'customer', 'K6 Customer'
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- participant: a guard (round-robin over the 200)
INSERT INTO chat.participants (conversation_id, user_id, user_role, display_name)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('99999999-0000-0000-0000-' || lpad(to_hex(((i - 1) % 200) + 1), 12, '0'))::uuid,
       'guard', 'K6 Guard ' || (((i - 1) % 200) + 1)
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- one message per conversation (sent by the guard so the customer's unread is exercised)
INSERT INTO chat.messages (conversation_id, sender_id, sender_role, content, message_type)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('99999999-0000-0000-0000-' || lpad(to_hex(((i - 1) % 200) + 1), 12, '0'))::uuid,
       'guard', 'k6 seed message ' || i, 'text'
FROM generate_series(1, 100) AS i
WHERE NOT EXISTS (
  SELECT 1 FROM chat.messages m
  WHERE m.conversation_id = ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid
);

-- ---- ratings for the first 50 guards (3 visible reviews each) for the summary read ---
INSERT INTO rating.guard_reviews (guard_id, customer_id, assignment_id, overall_rating, is_visible)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       'cccccccc-cccc-cccc-cccc-cccccccccccc',
       gen_random_uuid(),
       (g % 5) + 1, true
FROM generate_series(1, 50) AS g, generate_series(1, 3) AS r
WHERE NOT EXISTS (
  SELECT 1 FROM rating.guard_reviews gr
  WHERE gr.guard_id = ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid
);

-- ---- summary -------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM identity.users WHERE role = 'guard')                       AS guards,
  (SELECT count(*) FROM presence.guard_locations WHERE is_online)                  AS online_locs,
  (SELECT count(*) FROM booking.bookings WHERE status = 'accepted')                AS payable_bookings,
  (SELECT count(*) FROM chat.conversations)                                        AS conversations,
  (SELECT count(*) FROM rating.guard_reviews)                                      AS reviews;
