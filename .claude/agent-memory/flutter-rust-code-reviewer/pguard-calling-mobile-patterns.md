---
name: pguard-calling-mobile-patterns
description: Calling UI slice architecture, WebRTC lifecycle patterns, state machine hard rules, API contract alignment, and known patterns/bugs (2026-06-07)
metadata:
  type: project
---

## Calling UI slice (apps/mobile, pguard-mobile-call worktree)

**Key files:**
- `lib/core/models/call.dart` — Call/CallType/CallStatus, CallPhase/CallState, CallSignal(+kind) (PURE)
- `lib/core/calling/call_engine.dart` — Plugin-free CallEngine seam (SignalDescription/SignalCandidate/CallMediaEvent/CallException)
- `lib/core/calling/webrtc_call_engine.dart` — Production engine (flutter_webrtc + permission_handler); never built in tests
- `lib/core/network/sockets/call_socket.dart` — CallSignalFeed + CallSocket (/ws/call relay) + CallSignalFrame.tryParse
- `lib/core/controllers/call_controller.dart` — keepAlive singleton: state machine + ICE queue + signal routing + teardown
- `lib/features/call/{call_routes,call_screen}.dart` + widgets/{call_controls,call_entry_button}.dart

## Architecture (confirmed correct)

- **P2P relay**: The `/ws/call` endpoint is a plain SDP/ICE relay between two participants. The mediasoup SFU is service-JWT internal-only (only /health, /control/ping, /control/router-rtp-capabilities). Flutter uses flutter_webrtc P2P RTCPeerConnection with no mediasoup client.
- **Ready signal bootstrap**: The relay has no lifecycle/presence push. Callee sends `ready` on open; caller re-sends its offer in response. `_localOffer` stores the original offer.
- **call_id in frame, never URL**: Confirmed in CallSocket.send() and ws.rs.
- **Trickle ICE queue**: `_iceQueue` holds candidates until `_remoteSet=true`, then `_flushIce()`.
- **State machine**: idle → dialing|incoming → connecting → active → ended (terminal).
- **CallEngine seam**: `Object?` localStream/remoteStream keeps the seam plugin-free. Tests use FakeCallEngine.
- **Provider factories**: `callEngineFactoryProvider` (typedef `CallEngine Function()`) and `callSignalFeedBuilderProvider` (typedef `CallSignalFeed Function(tokenProvider)`) — same factory pattern as chatFeedBuilder.

## Signal frame wire shape

Outbound (client→relay):
```json
{ "type": "signal", "call_id": "<uuid>", "signal": { "kind": "offer|answer|candidate|ready|bye", "sdp"?: "...", "candidate"?: "...", "sdpMid"?: "...", "sdpMLineIndex"?: 0 } }
```
Inbound (relay→client):
```json
{ "type": "signal", "from": "<uuid>", "call_id": "<uuid>", "signal": { ... } }
```
Error: `{ "type": "error", "message": "<reason>" }`

## REST endpoints used by the controller

- `POST /calls/initiate` body `{booking_id, call_type}` → Call object
- `GET /calls/{id}` → Call object
- `PUT /calls/{id}/accept` → Call object
- `PUT /calls/{id}/reject` → Call object
- `PUT /calls/{id}/connected` → Call object
- `PUT /calls/{id}/end` → Call object (optional body `{reason}` — NOT sent by controller)

## Known structural issues (review 2026-06-07)

### Blocking
1. `_maybeAnswer` has a concurrent-call double-answer race. Both `accept()` → `await _maybeAnswer()` and the signal listener's `unawaited(_onRemoteOffer())` → `await _maybeAnswer()` can be in-flight simultaneously in Dart's async model. Both check `_remoteSet` before it's set to `true`, so both could proceed to call `setRemoteDescription` + send an answer. Fix: introduce a bool `_answerInFlight` flag set synchronously before the first `await`.

### Major
2. `CallState.copyWith` always clears `error` (does `error: error` not `error ?? this.error`). Any `copyWith()` call without an `error:` argument resets the field to null. Not currently hit (error only set in `_fail` which transitions to ended and tears down), but structurally wrong and latent.
3. `_ensureRenderers().then(_bindStreams)` called inline in `build()` with no stable guard beyond `_initialisingRenderers` — `_bindStreams` fires on every rebuild while in connecting/active phase. Non-crashing but wasteful.
4. No TURN server in WebRtcCallEngine ICE config — STUN-only means P2P fails behind symmetric NAT (common on Thai mobile networks). Deployment concern for production.

## CallState.copyWith fields that always reset (pattern antipattern)
- `error` always reset to null when not provided (unlike all other fields which use `??`)
