<!-- pguard v2 scaffold stub. See ../../../../../CLAUDE.md "Flutter (mobile)". -->

# core/network/sockets

**WebSocket lifecycle lives here — not in screens.**

Per CLAUDE.md (locked decision: "Mobile real-time = WebSocket subscription for
booking status, replaces 13-timer REST polling"):

- All `web_socket_channel` connect / subscribe / reconnect / dispose logic lives
  in this folder, owned by Riverpod providers (`@riverpod`).
- **No** `Timer.periodic` polling for booking/assignment status anywhere.
- Screens listen to controller/provider state; they never open sockets directly.
- Handle reconnect/backoff, auth token refresh on the socket, and clean teardown
  when the watching provider is disposed.

## TODO

- [ ] `BookingStatusSocket` — subscribes to live booking status pushes.
- [ ] `PresenceSocket` — guard GPS location stream (maps to `presence` service).
- [ ] Reconnect + exponential backoff + heartbeat handling.
- [ ] Attach + refresh auth token on the WS handshake.
