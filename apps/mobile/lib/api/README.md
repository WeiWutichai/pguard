<!-- pguard v2 scaffold stub. See ../../../CLAUDE.md "Architecture decisions". -->

# api

**Generated Dart API client — do not hand-write request models.**

Per CLAUDE.md (locked decision: "OpenAPI 3.1 as source of truth → codegen Rust
handler stubs + Dart + TS clients"):

- The Dart client is **generated** from the per-service OpenAPI specs in
  `contracts/openapi/` via `tooling/codegen/`.
- Generated code lands in `lib/api/generated/` and is **gitignored** (see the
  repo `.gitignore`); regenerate it, never edit it by hand.
- Hand-written wrappers (interceptors, auth-token injection on dio, error
  mapping) may live in `lib/api/` outside `generated/`.

## TODO

- [ ] Add the codegen invocation for the Dart client (`tooling/codegen/`).
- [ ] Add a dio client factory with auth-token + correlation-id interceptors.
- [ ] Ensure `lib/api/generated/` is listed in `.gitignore`.
