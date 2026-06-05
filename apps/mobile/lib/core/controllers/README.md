<!-- pguard v2 scaffold stub. See ../../../../CLAUDE.md "Flutter (mobile)". -->

# core/controllers

**Pure business logic — testable without widgets.**

Per CLAUDE.md ("Flutter (mobile)" Do/Don't):

- Put pure logic here: countdown math, proration, booking/assignment state
  machines, validation. No `BuildContext`, no widgets, no direct I/O.
- Expose state with Riverpod 2.x `@riverpod` codegen (run `dart run build_runner build`).
  **No** `Provider` / `ChangeNotifier` for new features.
- **No** business logic in screen state — screens render; controllers compute.
- These must be unit-testable in plain Dart (`test/`), no widget pumping required.

## TODO

- [ ] Add `BookingController` (state machine: requested → en_route → arrived → completed).
- [ ] Add `ProrationController` (port + improve v1 proration math).
- [ ] Add `SessionController` (auth/token lifecycle; reads from core/storage).
