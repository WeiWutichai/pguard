<!-- pguard v2. See ../../../../CLAUDE.md "API contracts" + tooling/codegen/README.md. -->

# api/ — Dart API client

`generated/` holds the **generated** Dart client, one package per service, codegen'd from
`contracts/openapi/*.yaml` by `tooling/codegen/generate.sh` (openapi-generator **dart-dio**,
pinned — see `tooling/codegen/README.md`). Hand-written wrappers (a dio factory with
auth-token + correlation-id interceptors, error mapping) may live here in `api/` **outside**
`generated/`.

## Status — generated, NOT yet adopted (read this)

- **Committed (not gitignored)**, like the web-admin TS client: the CI stale-check regenerates
  and `git diff --exit-code`s, so an OpenAPI edit that isn't regenerated fails CI. (Only the
  `build_runner` serializer outputs — `*.g.dart` — stay ignored; see below.)
- **Adoption is out of scope.** The existing mobile code keeps using its hand-written `dio`
  client (`lib/core/network/`). `generated/` is here as (a) a **compile-time proof that the
  current contracts are representable in Dart**, and (b) a starting point for *new* features.
  Nothing in the app imports it yet.
- **Excluded from `flutter analyze`** via `analysis_options.yaml` (`lib/api/generated/**`): each
  `generated/<svc>/` is a self-contained package (its own `pubspec.yaml` + deps), not part of the
  app's compilation unit, so the app analyze must not pull it in. The app stays green; the
  generated packages are validated **standalone** (see below).

## Using a generated client (when a new feature wants one)

Each `generated/<svc>/` is a dart-dio package using `built_value`, so it needs its serializers
built before it compiles:

```bash
cd apps/mobile/lib/api/generated/<svc>
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # emits the *.g.dart serializers (gitignored)
dart analyze                                                # standalone: clean except cosmetic unused-import warnings
```

Then add it as a path dependency in the app's `pubspec.yaml` and import
`package:pguard_<svc>_api/...`. (That step is the "adopt" follow-up, intentionally not done here.)

## Regenerate

Never hand-edit `generated/`. After any change to `contracts/openapi/*.yaml`:

```bash
./tooling/codegen/generate.sh        # regenerates TS + Dart + Rust event types
```
