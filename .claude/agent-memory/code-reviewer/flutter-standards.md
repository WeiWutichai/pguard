---
name: Flutter Standards
description: Riverpod patterns, controller extraction, shared widgets
type: project
---

# Flutter standards (Riverpod 2.x)

## Folder layout

```
apps/mobile/lib/
├── core/
│   ├── network/
│   │   ├── api_client.dart          ← Dio + JWT interceptor + OTel propagation
│   │   └── sockets/
│   │       ├── assignment_socket_service.dart   ← WS lifecycle out of screens
│   │       └── chat_socket_service.dart
│   ├── auth/
│   │   └── auth_repository.dart     ← token lifecycle, login/logout
│   ├── controllers/                 ← PURE controllers, testable
│   │   ├── countdown_controller.dart
│   │   ├── progress_report_manager.dart
│   │   └── pin_lockout_state_machine.dart
│   └── widgets/
│       └── pguard_header.dart       ← shared header (one source)
├── features/
│   ├── registration/                ← feature-scoped Riverpod providers
│   ├── active_job/
│   │   ├── providers/               ← @riverpod annotations
│   │   ├── widgets/
│   │   └── active_job_screen.dart   ← thin (≤ 400 LOC target)
│   └── ...
└── main.dart                        ← ProviderScope wrap
```

## Riverpod pattern (use codegen)

```dart
// features/active_job/providers/active_job_provider.dart
@riverpod
class ActiveJob extends _$ActiveJob {
  @override
  FutureOr<ActiveJobState?> build() async {
    final repo = ref.watch(activeJobRepositoryProvider);
    return repo.fetchActive();
  }

  Future<void> start() async { ... }
  Future<void> requestCompletion() async { ... }
}
```

In screen:
```dart
final state = ref.watch(activeJobProvider);
return state.when(
  data: (job) => job == null ? EmptyState() : ActiveJobView(job),
  loading: () => LoadingState(),
  error: (e, s) => ErrorState(e),
);
```

## Don't

- ❌ `ChangeNotifierProvider`, `Consumer<X>`, `context.watch<X>()` — use Riverpod
- ❌ `Timer.periodic` for booking/assignment status — use AssignmentSocketService
- ❌ Business logic in screen state — extract to controller
- ❌ Inline header markup — use `PGuardHeader` widget
- ❌ Direct API calls — go through repository (which uses generated client from OpenAPI)
- ❌ `SharedPreferences` for tokens or PIN hash — use `FlutterSecureStorage`

## State of common transitions

PIN flow (state machine in `core/controllers/pin_lockout_state_machine.dart`):
- valid → unlocked
- invalid (attempt < 5) → invalid with `remaining_before_lockout`
- invalid (attempt 5..9) → locked_out (60s countdown)
- invalid (attempt 10) → wiped (clear PIN hash, clear biometric, force re-OTP)

Active job timeline (`core/controllers/countdown_controller.dart` + `progress_report_manager.dart`):
- `started_at + booked_hours` = `end_at`
- Slot 0 = "start of work" popup at minute 0
- Slot k (k = 1..booked_hours) = popup at minute k × 60
- Missed slot → red warning, no retroactive submission

WebSocket assignment status (`core/network/sockets/assignment_socket_service.dart`):
- subscribes to `pguard.events.booking.{job_accepted, en_route, arrived, completed, cancelled}`
- emits domain events into Riverpod providers (no UI in service)
- reconnect with exponential backoff cap 60s
- token-refresh attempt before each reconnect (handle 401 once)
