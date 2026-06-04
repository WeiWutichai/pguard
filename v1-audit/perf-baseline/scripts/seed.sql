-- ============================================================================
-- pguard perf-baseline seed  (Phase 0.5 · B1)
-- Idempotent (ON CONFLICT DO NOTHING) — safe to re-run. Deterministic UUIDs so
-- the same rows are reused across runs.
--
-- Creates:
--   • 1 test customer  (phone 0820000001) + 1 test guard (phone 0810000001)
--   • 200 approved guards, ONLINE, GPS within ~25km of 13.7563,100.5018
--   • 100 guard_requests by the customer + 100 conversations (+participants+msg)
--   • the 100 request IDs double as the payable pool for payment-create.js
--
-- All accounts log in with password:  Password123!
-- (stored hash below is a real Argon2id hash of that string — verifies in v1)
--
-- Run:
--   docker compose exec -T postgres-db \
--     psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < seed.sql
--
-- Then export request IDs for payment-create.js:
--   docker compose exec -T postgres-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
--     -tAc "SELECT id FROM booking.guard_requests WHERE description='k6-seed'" \
--     | paste -sd, -
-- ============================================================================

\set ON_ERROR_STOP on

-- Argon2id hash of "Password123!" is inlined as a plain single-quoted literal
-- below (params are embedded in the string, so v1 verifies it regardless of its
-- own cost config). It is NOT a psql \set var on purpose: the '$' chars would
-- collide with psql dollar-quoting / variable handling.

-- ---- service rate (one active) -------------------------------------------------
INSERT INTO booking.service_rates (id, name, description, min_price, max_price, base_fee, min_hours, is_active)
VALUES ('5e51ce00-0000-0000-0000-000000000001', 'k6 Standard', 'k6 seed rate', 300, 5000, 300, 6, true)
ON CONFLICT DO NOTHING;

-- ---- test customer -------------------------------------------------------------
INSERT INTO auth.users (id, email, phone, password_hash, full_name, role, is_active, approval_status)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'k6cust@t.local', '0820000001', '$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU', 'K6 Customer', 'customer', true, 'approved')
ON CONFLICT DO NOTHING;

INSERT INTO auth.customer_profiles (user_id, full_name, contact_phone, email, company_name, address, approval_status)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'K6 Customer', '0820000001', 'k6cust@t.local', 'K6 Co', '123 Sukhumvit Rd, Bangkok 10110', 'approved')
ON CONFLICT DO NOTHING;

-- ---- test guard (used by gps-websocket.js) -------------------------------------
INSERT INTO auth.users (id, email, phone, password_hash, full_name, role, is_active, approval_status)
VALUES ('99999999-9999-9999-9999-999999999999', 'k6guard0@t.local', '0810000001', '$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU', 'K6 Guard 0', 'guard', true, 'approved')
ON CONFLICT DO NOTHING;
INSERT INTO auth.guard_profiles (user_id, years_of_experience)
VALUES ('99999999-9999-9999-9999-999999999999', 3)
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO tracking.guard_locations (guard_id, lat, lng, is_online, recorded_at)
VALUES ('99999999-9999-9999-9999-999999999999', 13.7563, 100.5018, true, NOW())
ON CONFLICT (guard_id) DO NOTHING;

-- ---- 200 approved, online guards within ~25km ----------------------------------
INSERT INTO auth.users (id, email, phone, password_hash, full_name, role, is_active, approval_status)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       'k6guard' || g || '@t.local',
       '0831' || lpad(g::text, 6, '0'),
       '$argon2id$v=19$m=65536,t=3,p=4$LbU9CkFUHEsr1K1nM9vtMA$MmK8h5n8I8BduGu0WAYl0UDBDPox0EFoigjHeCOZijU', 'K6 Guard ' || g, 'guard', true, 'approved'
FROM generate_series(1, 200) AS g
ON CONFLICT DO NOTHING;

INSERT INTO auth.guard_profiles (user_id, years_of_experience)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, (g % 10) + 1
FROM generate_series(1, 200) AS g
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO tracking.guard_locations (guard_id, lat, lng, is_online, recorded_at)
SELECT ('99999999-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid,
       13.7563 + (random() - 0.5) * 0.4,   -- ±0.2° lat  ≈ ±22 km
       100.5018 + (random() - 0.5) * 0.4,  -- ±0.2° lng  ≈ ±22 km
       true, NOW()
FROM generate_series(1, 200) AS g
ON CONFLICT (guard_id) DO NOTHING;

-- ---- 100 requests by the customer (back conversations + payable pool) -----------
INSERT INTO booking.guard_requests
       (id, customer_id, location_lat, location_lng, address, description, status, urgency, booked_hours, guard_count)
SELECT ('11111111-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       'cccccccc-cccc-cccc-cccc-cccccccccccc',
       13.7563, 100.5018, 'Seed site #' || i, 'k6-seed', 'pending', 'medium', 4, 1
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- ---- 100 conversations (customer + a guard) + 1 message each --------------------
INSERT INTO chat.conversations (id, request_id)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('11111111-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- participant: customer
INSERT INTO chat.conversation_participants (conversation_id, user_id)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       'cccccccc-cccc-cccc-cccc-cccccccccccc'
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- participant: a guard (round-robin over the 200)
INSERT INTO chat.conversation_participants (conversation_id, user_id)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('99999999-0000-0000-0000-' || lpad(to_hex(((i - 1) % 200) + 1), 12, '0'))::uuid
FROM generate_series(1, 100) AS i
ON CONFLICT DO NOTHING;

-- one message per conversation (sent by the guard so customer's unread is exercised)
-- idempotent: skip conversations that already have a seeded message
INSERT INTO chat.messages (conversation_id, sender_id, content, message_type)
SELECT ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid,
       ('99999999-0000-0000-0000-' || lpad(to_hex(((i - 1) % 200) + 1), 12, '0'))::uuid,
       'k6 seed message ' || i, 'text'
FROM generate_series(1, 100) AS i
WHERE NOT EXISTS (
  SELECT 1 FROM chat.messages m
  WHERE m.conversation_id = ('22222222-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid
);

-- ---- summary -------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM auth.users WHERE email LIKE 'k6guard%')            AS guards,
  (SELECT count(*) FROM tracking.guard_locations WHERE is_online)          AS online_locs,
  (SELECT count(*) FROM booking.guard_requests WHERE description='k6-seed') AS requests,
  (SELECT count(*) FROM chat.conversations
     WHERE id::text LIKE '22222222-%')                                     AS conversations;
