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

  /// Signed OUT but the device still REMEMBERS the account (a local PIN + the login phone), e.g.
  /// after a normal logout. There are NO tokens — the user re-authenticates by entering their PIN
  /// (mints a fresh token pair via `POST /auth/login`), NOT by redoing OTP + a brand-new PIN. This
  /// is distinct from [locked] (which presumes tokens exist and unlocks OFFLINE) and from
  /// [unauthenticated] (a truly fresh device with no remembered account). "Use a different account"
  /// / "forgot PIN" drop from here to [unauthenticated].
  returning,

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
      if (onboarding != null) {
        state = const SessionState(SessionStatus.onboardingRole);
        return;
      }
      // A REMEMBERED device (local PIN + login phone, but no tokens — logged out earlier) resumes at
      // the PIN-login screen (mint fresh tokens), NOT the full OTP registration. A truly fresh device
      // (no PIN / no phone) → unauthenticated.
      final hasPin = await store.hasPin();
      final phone = hasPin ? await store.readPhone() : null;
      if (_disposed || state.status != SessionStatus.unknown) return;
      state = SessionState((hasPin && phone != null)
          ? SessionStatus.returning
          : SessionStatus.unauthenticated);
      return;
    }
    final access = await store.readAccessToken();
    if (_disposed || state.status != SessionStatus.unknown) return;
    // The enrolled roles were persisted (non-sensitive) at login so a cold start can land on the
    // mode picker when the account holds >1 role. The access token's `role` is still the ACTIVE one.
    // Best-effort: a prefs read failure degrades to "only the active role known" — the live session
    // still works (the active role is the fallback) and the next `GET /auth/me` refreshes the set.
    List<String> enrolled;
    try {
      enrolled = _parseRoles(await prefs.getString(kEnrolledRolesKey));
    } catch (_) {
      enrolled = const [];
    }
    if (_disposed || state.status != SessionStatus.unknown) return;
    final user = access != null
        ? AuthUser(
            userId: Jwt.subject(access) ?? '',
            role: Jwt.role(access) ?? '',
            roles: enrolled)
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

  /// After a successful login (tokens already persisted). Persists the enrolled-role set
  /// (non-sensitive) so a cold start can land on the mode picker for a dual-role account.
  void onLoggedIn(AuthUser user) {
    _persistRoles(user.enrolledRoles);
    state = SessionState(SessionStatus.authenticated, user: user);
  }

  /// After a successful `POST /auth/switch-role` (the new token pair is already persisted by the
  /// caller). Swaps the ACTIVE role while keeping the enrolled set, so the router redirects to the
  /// new role's home WITHOUT logging out. No prefs write — the enrolled set is unchanged.
  void switchActiveRole(String role) {
    final user = state.user;
    if (user == null) return;
    state = SessionState(SessionStatus.authenticated,
        user: user.withActiveRole(role));
  }

  /// Refresh the enrolled-role set from `GET /auth/me` (it may have grown after an admin approved a
  /// newly-enrolled role). Persists it and re-emits so the homes/picker see the updated set.
  void refreshRoles(List<String> roles) {
    final user = state.user;
    if (user == null || state.status != SessionStatus.authenticated) return;
    _persistRoles(user.withRoles(roles).enrolledRoles);
    state = SessionState(SessionStatus.authenticated,
        user: user.withRoles(roles));
  }

  /// After clearing the PIN gate on cold start.
  void onUnlocked() =>
      state = SessionState(SessionStatus.authenticated, user: state.user);

  /// The onboarding phone-verified token expired/was consumed (register rejected with 401/400):
  /// the first segment must be redone, so drop to unauthenticated → router sends to `/auth/phone`.
  void onOnboardingExpired() =>
      state = const SessionState(SessionStatus.unauthenticated);

  /// Leave the current gated screen (locked / returning) to run the OTP-based PIN RESET flow, which
  /// lives under /auth/*. `returning` permits /auth/* (and /login/pin), so the captcha → OTP → new-PIN
  /// reset can run; it ends in a fresh login → authenticated. Safe from `locked` too — a forgotten
  /// PIN can't unlock offline anyway, and the reset mints new tokens that supersede the stored ones.
  void beginPinReset() => state = const SessionState(SessionStatus.returning);

  /// Re-lock without dropping tokens (e.g., on app resume).
  void lock() {
    if (state.status == SessionStatus.authenticated) {
      state = SessionState(SessionStatus.locked, user: state.user);
    }
  }

  /// Sign out. By DEFAULT the device is REMEMBERED: the login phone is kept (re-saved — clearSession
  /// drops it) and the local PIN is left in place, so the session lands on [SessionStatus.returning]
  /// → the user gets back in with just their PIN (no OTP, no new PIN). Pass [forgetDevice] = true for
  /// a FULL sign-out ("use a different account" / a forgotten PIN) — the phone is dropped and the
  /// local PIN wiped, so the device is a fresh [SessionStatus.unauthenticated] → the OTP flow.
  Future<void> logout({bool forgetDevice = false}) async {
    final store = ref.read(appStoreProvider);
    // Capture the login identifier BEFORE clearing storage — a remembered device re-authenticates
    // by PIN, which needs the phone.
    final phone = await store.readPhone();
    final hasPin = !forgetDevice && await store.hasPin();
    if (forgetDevice) {
      // Full teardown: tokens + phone + the local PIN (hash/salt/lockout) + biometric flag — a truly
      // fresh device, so the remembered-device classification can't re-trigger.
      await store.wipe();
    } else {
      // Keep the local PIN so the remembered device can re-login by PIN.
      await store.clearSession();
    }
    // Also clear any pending-registration prefs so a stale flag can't strand a cold start on the
    // pending screen after logout (independent of which login path ran). clearSession() already
    // drops the secure-storage registration tokens.
    final prefs = ref.read(prefsStoreProvider);
    await prefs.remove(kRegPendingRoleKey);
    await prefs.remove(kRegSummaryKey);
    // Drop the persisted enrolled-role set so a logged-out device doesn't carry one account's roles
    // into the next user's cold-start classification.
    await prefs.remove(kEnrolledRolesKey);
    // Drop the onboarding-resume marker + raw PIN too, so a logged-out device never resumes a
    // half-finished registration (and no raw PIN lingers). clearSession() already removed the
    // onboarding PIN, but remove the prefs marker here.
    await prefs.remove(kRegOnboardingStageKey);
    // The auth-flow controller is keepAlive, so clear its cross-screen state (phone, OTP,
    // phone-verified token) here — otherwise a next registration would start with the previous
    // user's phone/token lingering.
    ref.read(authControllerProvider.notifier).reset();
    if (hasPin && phone != null) {
      // Remembered device: re-persist the phone (clearSession dropped it) and land on the PIN-login
      // screen. The local PIN is untouched, so the returning login can proceed offline-then-online.
      await store.savePhone(phone);
      state = const SessionState(SessionStatus.returning);
    } else {
      state = const SessionState(SessionStatus.unauthenticated);
    }
  }

  /// Persist the enrolled roles as a comma-separated label list (non-sensitive → prefs).
  /// Fire-and-forget: the in-memory state is the source of truth for the live session; this is only
  /// the cold-start hint, so a slow write never blocks the redirect. Errors are swallowed (a failed
  /// hint write just means a future cold start re-derives the set from the access token + /auth/me).
  void _persistRoles(List<String> roles) {
    ref
        .read(prefsStoreProvider)
        .setString(kEnrolledRolesKey, roles.join(','))
        .catchError((_) {});
  }

  /// Parse the persisted comma-separated enrolled-role list (null/empty → empty list).
  static List<String> _parseRoles(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final r in raw.split(','))
        if (r.isNotEmpty) r,
    ];
  }
}
