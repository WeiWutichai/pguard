<!-- pguard v2 scaffold stub. See ../../CLAUDE.md "Flutter (mobile)". -->

# pguard_mobile

Customer-side Flutter app for **pguard** — book on-demand security guards.
Bilingual **TH/EN**. State managed with **Riverpod 2.x (codegen)**.

> v2 of guard-dispatch. v1 is a read-only reference at `../../../guard-dispatch/`;
> never edit or copy it. See repo root `CLAUDE.md` for architecture decisions.

## Run

```bash
flutter pub get
dart run build_runner build   # generates Riverpod providers (*.g.dart)
flutter run
```

For active codegen during development:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Conventions (from CLAUDE.md "Flutter (mobile)")

- **Riverpod 2.x with `@riverpod` codegen.** No `Provider` / `ChangeNotifier`
  for new features.
- **No `Timer.periodic` polling** for booking/assignment status — real-time
  updates arrive over a **WebSocket** (`lib/core/network/sockets/`).
- **Pure logic** (countdown math, proration, state machines) lives in
  `lib/core/controllers/`, testable without widgets — not in screen state.
- **No god-screens > 800 LOC** — extract widgets + controllers.
- Tokens + PIN hash → `FlutterSecureStorage`; non-sensitive prefs →
  `SharedPreferences` (`lib/core/storage/`).
- Reuse the shared `PGuardHeader` widget (`lib/widgets/`) — don't copy-paste
  header markup.

## Layout

```
lib/
├── main.dart                  ProviderScope + MaterialApp (placeholder)
├── core/
│   ├── controllers/           pure, testable logic (Riverpod codegen)
│   ├── network/sockets/       WebSocket lifecycle (no polling)
│   └── storage/               secure storage vs. prefs
├── features/                  per-feature screens + controllers
├── api/                       generated Dart client → api/generated/ (gitignored)
└── widgets/                   shared widgets (PGuardHeader, ...)
test/
└── smoke_test.dart            harness sanity check
```

## Testing

```bash
flutter test
```
