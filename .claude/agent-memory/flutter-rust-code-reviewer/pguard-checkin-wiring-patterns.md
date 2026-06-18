---
name: pguard-checkin-wiring-patterns
description: Guard hourly check-in wiring patterns, slot-to-hour mapping, 409 disambiguation, ProgressReport model, and test patterns (2026-06-10)
metadata:
  type: project
---

## Check-in capture additions (feat/mobile-checkin-capture — PR #30)

**Three changes in this slice:**
1. `ImagePickerPhotoCaptureService` (new) — `ImageSource.camera`, `imageQuality: 80, maxWidth: 2000` (matches chat picker). `XFile.length()` for size. Cancel→null, PlatformException→null. Injectable `pick` seam for tests. `UnavailablePhotoCaptureService` stays as the interface fallback; `providers.dart` flips default to the real one.
2. `CheckInSchedule.totalSlots` = `hours` (was `hours+1`). Slots 0..hours-1. `dueIndex` capped at `hours-1`. `nextDueAt` returns null when the final slot is already due. PR #29 end-of-shift slot removed — each slot maps 1:1 to a server hour (slot N → hour N+1, always in 1..hours). The defensive clamp in `submitCheckIn` is unreachable for valid slot indices.
3. `validateStatus` in `ApiClient` now excludes 401 (`s != 401`), making 401 a DioException that reaches `_onError` for reactive refresh+retry. Previously 401 was a normal response and `_onError` never fired (dead reactive path). Other 4xx (400/403/404/409/413) still land in `_send` as ApiException. Proactive refresh in `_onRequest` untouched.

**Known edge: hours=0** — `CheckInSchedule` for a 0-hour booking produces `dueIndex=0` (phantom slot) and `isDueNow=true`. In practice unreachable (bookings always have hours≥1), but not guarded in the schedule.

## Check-in service architecture (feat/mobile-checkin-wiring)

**Key files:**
- `lib/core/network/check_in_service.dart` — `ApiCheckInService` (multipart POST)
- `lib/core/models/progress_report.dart` — ProgressReport model (pure)
- `lib/core/controllers/active_job_controller.dart` — `submitCheckIn()` slot→hour mapping
- `lib/features/guard/widgets/check_in_sheet.dart` — UI (unchanged in this slice)

## API contract (POST /v1/bookings/{id}/progress-reports)

- multipart/form-data: `hour_number` (int as string), `photo` (single file part, MIME image/jpeg|png|webp), `lat`+`lng` (optional pair), `accuracy` (optional float), `note` (optional, ≤2000, trimmed, omitted when empty)
- Response 200: `{ data: ProgressReport }` with `accuracy_m` (NOT `accuracy`) in response body
- Wire asymmetry: REQUEST = `accuracy`, RESPONSE = `accuracy_m`
- 409 has TWO meanings disambiguated by message text: "already exists"/"duplicate" = absorbed as success; otherwise = "too early"
- 413 at EDGE today (gateway MAX_BODY_BYTES = 1MiB cap → fires before booking service's 12MiB cap)

## Slot↔hour mapping

- CheckInSchedule slots are 0-based (slot 0 = start check-in, slot N = after N elapsed hours)
- Server hour_number is 1-based (1..hours)
- Mapping: serverHour = (slot + 1).clamp(1, hours) — prevents sending hour_number=0 and prevents slot hours (slot+1=hours+1) from exceeding hours
- completedCheckIns stays slot-indexed (so dueIndex/missed in CheckInSchedule still work)
- submitCheckIn parameter is named `hourNumber` but is semantically the 0-based UI slot (naming is misleading but not a bug)

## 409 disambiguation heuristic

- `_isDuplicateHour()`: checks `e.statusCode == 409` AND message.toLowerCase() contains "already exists" or "duplicate"
- No machine-readable sub-code in the 409 response (both cases have code: CONFLICT); string match is the only option
- If server changes its error message wording, duplicate-hour 409 could be misclassified as "too early"

## ProgressReport model

- `id`, `bookingId`, `guardId`, `hourNumber`, `photoKey`, `photoUrl`, `createdAt` — required
- `lat`, `lng`, `accuracyM`, `note` — nullable
- `photoUrl` is a fresh presigned GET URL (TTL 1h); never persist it
- `createdAt` falls back to `DateTime.now().toUtc()` on parse failure

## FakeCheckInService (test/support/fakes.dart)

- Records submitted `hourNumber` values in `List<int> submitted`
- `fail: true` constructor arg throws `ApiException(message: 'check-in failed')`
- Signature unchanged from PendingCheckInService (no breaking change for existing tests)

## Test pattern: real ApiClient with _StubAdapter

- `_StubAdapter` implements `HttpClientAdapter`, routes by `options.path` (Dio v5 path = as-provided string, NOT full URL)
- Used for the proactive-refresh integration test (token-refresh + multipart upload)
- `_StubAdapter` is new to this codebase; only appears in check_in_service_test.dart
