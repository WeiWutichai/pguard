# mediasoup (SFU) — Node service

> v2 scaffold placeholder. The only **non-Rust** service in `services/`.

MediaSoup SFU for WebRTC media routing, paired with the Rust `calling` service
(which owns WebRTC **signaling** + WebRTC↔SFU orchestration). Built out in
**Phase 3 — Split booking** (`call → payment → rating → assignment`).

## v2 hardening (must-do when implemented)
- **Service-JWT** on all control-plane endpoints (v1's SFU control had no auth —
  see CLAUDE.md "Service auth (internal)"). Validate the `pguard-internal`
  audience service token issued by `calling`.
- No direct DB access — `calling` owns the schema; this process is media-only.

## Run (later)
```bash
cd services/mediasoup && pnpm install && pnpm dev
```
