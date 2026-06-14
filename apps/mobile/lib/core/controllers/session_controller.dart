import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../models/registration.dart';
import '../network/jwt.dart';
import '../providers.dart';
import 'auth_controller.dart';

part 'session_controller.g.dart';

/// Where the app should route the user.
enum SessionStatus {
  /// Still loading from secure storage (show splash).
  unknown,

  /// No session — go to the phone/OTP auth flow.
  unauthenticated,

  /// First onboarding segment done (phone→OTP→PIN) but role not yet chosen → resume at
  /// role-select on cold start instead of forcing phone/OTP/PIN again. The actionable
  /// credentials (phone, phone-verified token, raw PIN) are in secure storage.
  onboardingRole,

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
    // _load is the STARTUP classifier only. If an explicit transition (onLoggedIn /
    // onPendingApproval / onOnboardingExpired) already moved us off `unknown` while these
    // reads were in flight, never clobber it with a stale read (e.g. a just-logged-in user
    // would otherwise flip back to `locked`).
    if (_disposed || state.status != SessionStatus.unknown) return;
    if (refresh == null) {
      // No session. Precedence: a registered-but-pending account (pending flag, set after
      // profile submit) is furthest along → pendingApproval. Else, if the first onboarding
      // segment finished (phone→OTP→PIN) but role wasn't chosen, resume at role-select
      // (onboardingRole) so we don't force phone/OTP/PIN again. Otherwise a fresh start.
      final pending =
          RegistrationRole.tryParse(await prefs.getString(kRegPendingRoleKey));
      if (_disposed || state.status != SessionStatus.unknown) return;
      if (pending != null) {
        state = const SessionState(SessionStatus.pendingApproval);
        return;
      }
      final onboarding = await prefs.getString(kRegOnboardingStageKey);
      if (_disposed || state.status != SessionStatus.unknown) return;
      state = SessionState(onboarding != null
          ? SessionStatus.onboardingRole
          : SessionStatus.unauthenticated);
      return;
    }
    final access = await store.readAccessToken();
    if (_disposed || state.status != SessionStatus.unknown) return;
    final user = access != null
        ? AuthUser(
            userId: Jwt.subject(access) ?? '', role: Jwt.role(access) ?? '')
        : null;
    // A configured PIN means a cold start must be unlocked before use.
    final hasPin = await store.hasPin();
    if (_disposed || state.status != SessionStatus.unknown) return;
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

  /// The onboarding phone-verified token expired/was consumed (register rejected with 401/400):
  /// the first segment must be redone, so drop to unauthenticated → router sends to `/auth/phone`.
  void onOnboardingExpired() =>
      state = const SessionState(SessionStatus.unauthenticated);

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
    // Drop the onboarding-resume marker + raw PIN too, so a logged-out device never resumes a
    // half-finished registration (and no raw PIN lingers). clearSession() already removed the
    // onboarding PIN, but remove the prefs marker here.
    await prefs.remove(kRegOnboardingStageKey);
    // The auth-flow controller is keepAlive, so clear its cross-screen state (phone, OTP,
    // phone-verified token) here — otherwise a next registration would start with the previous
    // user's phone/token lingering.
    ref.read(authControllerProvider.notifier).reset();
    state = const SessionState(SessionStatus.unauthenticated);
  }
}
