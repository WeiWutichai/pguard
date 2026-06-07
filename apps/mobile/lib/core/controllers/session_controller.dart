import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../models/registration.dart';
import '../network/jwt.dart';
import '../providers.dart';

part 'session_controller.g.dart';

/// Where the app should route the user.
enum SessionStatus {
  /// Still loading from secure storage (show splash).
  unknown,

  /// No session — go to the phone/OTP auth flow.
  unauthenticated,

  /// Registered but NOT yet approved — no tokens, can't log in. Stays in the registration
  /// sub-flow (profile form / pending screen) until approval (then login succeeds).
  pendingApproval,

  /// Session exists but a PIN gate must be cleared first (cold start).
  locked,

  /// Fully signed in — route to the role dashboard.
  authenticated,
}

class SessionState {
  const SessionState(this.status, {this.user});
  final SessionStatus status;
  final AuthUser? user;
}

/// App session state — the router redirect watches this. Pure transitions; the async load
/// reads secure storage once at startup. Tokens are refreshed lazily by the [ApiClient];
/// here we only classify "do we have a session + is it locked".
@Riverpod(keepAlive: true)
class Session extends _$Session {
  bool _disposed = false;

  @override
  SessionState build() {
    ref.onDispose(() => _disposed = true);
    Future.microtask(_load);
    return const SessionState(SessionStatus.unknown);
  }

  Future<void> _load() async {
    // Capture providers BEFORE any await (never `ref.read` after an await) and bail if the
    // container was disposed mid-load — avoids the "use ref after dispose" footgun.
    final store = ref.read(appStoreProvider);
    final prefs = ref.read(prefsStoreProvider);
    final refresh = await store.readRefreshToken();
    if (_disposed) return;
    if (refresh == null) {
      // No session. A persisted pending-registration flag (set at register, no tokens) resumes
      // the pending sub-flow across a cold start; otherwise it's a fresh unauthenticated start.
      final pending =
          RegistrationRole.tryParse(await prefs.getString(kRegPendingRoleKey));
      if (_disposed) return;
      state = SessionState(pending != null
          ? SessionStatus.pendingApproval
          : SessionStatus.unauthenticated);
      return;
    }
    final access = await store.readAccessToken();
    if (_disposed) return;
    final user = access != null
        ? AuthUser(
            userId: Jwt.subject(access) ?? '', role: Jwt.role(access) ?? '')
        : null;
    // A configured PIN means a cold start must be unlocked before use.
    final hasPin = await store.hasPin();
    if (_disposed) return;
    state = hasPin
        ? SessionState(SessionStatus.locked, user: user)
        : SessionState(SessionStatus.authenticated, user: user);
  }

  /// After `POST /auth/register` (202): registered but pending approval — NO tokens, NOT
  /// authenticated. The router keeps the user in the registration sub-flow until approval.
  void onPendingApproval() =>
      state = const SessionState(SessionStatus.pendingApproval);

  /// After a successful login (tokens already persisted).
  void onLoggedIn(AuthUser user) =>
      state = SessionState(SessionStatus.authenticated, user: user);

  /// After clearing the PIN gate on cold start.
  void onUnlocked() =>
      state = SessionState(SessionStatus.authenticated, user: state.user);

  /// Re-lock without dropping tokens (e.g., on app resume).
  void lock() {
    if (state.status == SessionStatus.authenticated) {
      state = SessionState(SessionStatus.locked, user: state.user);
    }
  }

  Future<void> logout() async {
    await ref.read(appStoreProvider).clearSession();
    // Also clear any pending-registration prefs so a stale flag can't strand a cold start on the
    // pending screen after logout (independent of which login path ran). clearSession() already
    // drops the secure-storage registration tokens.
    final prefs = ref.read(prefsStoreProvider);
    await prefs.remove(kRegPendingRoleKey);
    await prefs.remove(kRegSummaryKey);
    state = const SessionState(SessionStatus.unauthenticated);
  }
}
