-- pguard presence-service — fence the offline write on a per-connection session token.
--
-- `guard_locations` is ONE row per guard (0002). On ANY WS session exit the service runs an
-- UNCONDITIONAL `UPDATE ... SET is_online = false WHERE guard_id = $1`. With at-least-once
-- reconnection, a LATE-closing OLD socket can therefore flip a freshly-reconnected LIVE session
-- offline (last-disconnect-wins) — the new socket goes dark on the map until its next fix.
--
-- Fix: stamp each upsert with the OWNING session's UUID (generated at session start) and fence
-- the offline write on it: only the session that currently owns the row may mark it offline. A
-- stale OLD socket's `connected_session` no longer matches → its offline UPDATE is a no-op.
--
-- Nullable + no backfill: existing rows predate session tracking; the first fix from any live
-- session stamps the column. No CONCURRENTLY needed for a plain ADD COLUMN (metadata-only,
-- no table rewrite for a nullable column with no default).

ALTER TABLE presence.guard_locations
    ADD COLUMN connected_session UUID;
