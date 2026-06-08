# mobile — calling UI (WebRTC voice/video) — work spec

> For Claude Code (Terminal A). Build the call screens against the **merged** calling backend
> (`contracts/openapi/calling.yaml` — REST control + `GET /ws/call` signaling; media plane =
> Node mediasoup SFU brokered by calling). Reuse the existing `ws_client` for signaling.
> **Contracts are source of truth.** Branch off freshly synced main. Don't merge; don't touch
> `../guard-dispatch/`.

## Setup
```bash
git checkout main && git pull          # c7ff826
git worktree add ../pguard-mobile-call -b feat/mobile-calling-ui main
cd ../pguard-mobile-call
```

## Backend contract (already merged — build to this)
- `POST /calls/initiate` `{ booking_id, callee_id, media: audio|video }` → call id (allowed only with an ACTIVE booking — backend verifies via booking's service-JWT).
- `GET /calls/{id}` (state), `PUT /calls/{id}/accept`, `PUT /calls/{id}/reject`, `PUT /calls/{id}/end` (confirm exact verbs/paths in `calling.yaml`).
- WS `GET /ws/call` — **Bearer-on-upgrade**; after open send `{ type: "signal", call_id, signal: <opaque SDP/ICE> }`; server relays `{ type:"signal", from, call_id, signal }` to the other participant only (IDOR-safe on the wire). Call lifecycle events also arrive on this socket.
- Events on the bus (informational): `calling.initiated/accepted/rejected/ended`.

## Scope

### A. WebRTC plumbing
- Add `flutter_webrtc` (+ a mediasoup client if the SFU requires it — check `services/mediasoup/src/sfu.js` for the transport/produce/consume handshake; if the signaling is plain SDP/ICE relay, `flutter_webrtc` + the `/ws/call` relay is enough). Permissions: mic (audio) + camera (video) in `AndroidManifest.xml` / `Info.plist` (`NSMicrophoneUsageDescription`, `NSCameraUsageDescription`).
- `CallController` (Riverpod `@riverpod`): owns the `RTCPeerConnection`, local/remote `MediaStream`, ICE candidate queue, and the signaling socket (via `ws_client`, Bearer-on-upgrade). Pure call-state machine (idle→ringing→connecting→active→ended) in the controller — unit-testable without the platform plugin (inject a fake peer/socket).

### B. Screens
- **Outgoing**: from chat/job-detail "call" button (audio/video) → `POST /calls/initiate` → ringing screen (callee name/avatar, cancel).
- **Incoming**: a `calling.initiated` push (over the WS / notification) → full-screen incoming UI (accept/reject) → `PUT accept`/`reject`.
- **In-call**: local preview + remote view (video) or avatar (audio); mute, speaker, camera-flip, end. End → `PUT end` + teardown.
- Reuse `PGuardHeader`-style; keep all media/WebRTC lifecycle in the controller, never widget state. Dispose → close peer + socket + release tracks.

### C. Signaling
- conversation/call id sent in the signal frame (not URL). Trickle ICE (queue candidates until remote description set). Re-auth/reconnect via `ws_client` (Bearer refresh on reconnect, mirror tracking/chat). No `Timer.periodic`.

## Definition of Done
- `flutter analyze` ✅ · `flutter test` ✅ · `build_runner` ok (`.g.dart` gitignored — DoD assumes regen).
- **Controller unit tests** (no platform plugin): call-state machine transitions; ICE-candidate queue/flush; accept/reject/end → correct REST verb; signal relay routing; teardown on dispose/end.
- Widget tests: incoming (accept/reject), in-call controls (mute/end), ringing.
- Permissions declared (mic + camera). No WebRTC lifecycle in widgets.
- Update `PROGRESS.md` (tick calling-mobile under Phase 3 + Completed-log row) · run the review agents (flutter-rust-code-reviewer + code-reviewer + architecture-guardian) · own PR off main · **don't merge**.

## Reference (read-only)
- Contracts: `contracts/openapi/calling.yaml`; SFU handshake: `services/mediasoup/src/{sfu,server,auth}.js`; backend signaling: `services/calling/src/api/ws.rs`. Reuse: `apps/mobile/lib/core/network/sockets/{ws_client,backoff}.dart`, `features/chat/*` (entry button pattern).
- v1 UX to port (cite paths; adapt to Riverpod + flutter_webrtc + v2 `/v1` contract): `../guard-dispatch/frontend/mobile/lib/screens/*call*` (if present) — but v2's signaling shape is the `calling.yaml` relay, not v1's. Mediasoup client usage in v1 web/mobile is reference only.
