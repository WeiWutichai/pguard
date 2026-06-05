import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../network/jwt.dart';
import '../providers.dart';

part 'session_controller.g.dart';

/// Where the app should route the user.
enum SessionStatus {
  /// Still loading from secure storage (show splash).
  unknown,

  /// No session — go to the phone/OTP auth flow.
  unauthenticated,

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
  @override
  SessionState build() {
    Future.microtask(_load);
    return const SessionState(SessionStatus.unknown);
  }

  Future<void> _load() async {
    final store = ref.read(appStoreProvider);
    final refresh = await store.readRefreshToken();
    if (refresh == null) {
      state = const SessionState(SessionStatus.unauthenticated);
      return;
    }
    final access = await store.readAccessToken();
    final user = access != null
        ? AuthUser(
            userId: Jwt.subject(access) ?? '', role: Jwt.role(access) ?? '')
        : null;
    // A configured PIN means a cold start must be unlocked before use.
    final hasPin = await store.hasPin();
    state = hasPin
        ? SessionState(SessionStatus.locked, user: user)
        : SessionState(SessionStatus.authenticated, user: user);
  }

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
    state = const SessionState(SessionStatus.unauthenticated);
  }
}
