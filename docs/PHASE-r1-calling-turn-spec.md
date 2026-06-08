# Round 1 · calling end-to-end — STUN/TURN for real 2-party calls — work spec

> For Claude Code (Terminal B). Mobile calling is **P2P WebRTC** (SDP/ICE relayed over the calling
> `/ws/call` socket — `webrtc_call_engine.dart`: *"no SFU client"*). The signaling + UI are done;
> the gap is **NAT traversal**: without STUN/TURN, P2P only connects on the same LAN. Add a TURN
> server + wire the ICE config so a real call connects across networks. (The mediasoup SFU is a
> separate, optional path for **group** calls — out of scope here; this also sidesteps the
> mediasoup RTC-port/Tailscale 41641 conflict, since 2-party calls don't need the SFU.) Branch off
> freshly synced main. Don't merge; don't touch `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # 2a40357
git worktree add ../pguard-turn -b feat/r1-calling-turn main
cd ../pguard-turn
```

## Scope

### A. TURN/STUN infra
- Add **coturn** to `infra/docker/docker-compose.prod.yml` (its own service; UDP/TCP relay ports + a sane port range; long-term-credential auth). Secrets via `${VAR:?}` (`TURN_SECRET`/realm). Document the ports + that in prod the TURN server needs a public IP / the announced address (the CGNAT note the calling slice flagged).
- Don't break the gateway-only-host-ports rule unduly: TURN inherently needs reachable relay ports — document this as the one justified exception (media can't proxy through the HTTP gateway), scoped + commented.

### B. Serve ICE config to clients
- The calling service exposes the **ICE server list** (STUN + TURN URLs + short-lived TURN credentials, ideally HMAC time-limited from `TURN_SECRET`) to an authenticated caller — e.g. on call initiate/accept or a `GET /calls/ice` style endpoint (confirm/extend `contracts/openapi/calling.yaml`). Credentials must be per-call/short-lived, never static in the client.
- Mobile `CallController`/`webrtc_call_engine` consumes the served ICE list when building the `RTCPeerConnection` (instead of a hard-coded/empty ICE config). Keep the CallEngine seam (controller passes config in; engine stays plugin-thin + testable).

### C. Verify a real call
- Prove a 2-party audio (and video) call actually **connects** (ICE state → connected, media flows) across two devices/networks using the TURN relay — document the manual verification steps + a scripted ICE-gathering test where possible.

## Definition of Done
- coturn in the prod compose with `${VAR:?}` creds + documented relay ports + the CGNAT/public-IP note.
- Calling service serves a short-lived ICE config (STUN+TURN) to authenticated callers; contract updated.
- Mobile builds the peer connection from the served ICE list (no hard-coded ICE); CallController tests cover "ICE config applied" + teardown; `flutter analyze`/`test` green.
- A documented end-to-end call verification (ICE connected + media) over the relay.
- `cargo clippy -D warnings` + `cargo test --workspace` green (calling changes). Update `PROGRESS.md` (tick calling-e2e/TURN + Completed-log row) · run the review agents (security-reviewer on the TURN credential flow + code + architecture) · own PR off main · **don't merge**.

## Reference (read-only)
- Mobile: `apps/mobile/lib/core/calling/{call_engine,webrtc_call_engine}.dart`, `core/controllers/call_controller.dart`, `core/network/sockets/call_socket.dart`. Backend: `services/calling/src/api/ws.rs` (signaling), `contracts/openapi/calling.yaml`. Compose + secrets: `infra/docker/docker-compose.prod.yml` + `infra/.env.perf.example`/`README.md`. The calling-UI slice's TURN/CGNAT note is in `PROGRESS.md` (mobile calling row).
