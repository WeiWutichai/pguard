import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../models/registration.dart';
import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../network/jwt.dart';
import '../providers.dart';
import 'customer_home_controller.dart';
import 'guard_jobs_controller.dart';
import 'guard_ratings_controller.dart';
import 'locale_controller.dart';
import 'profile_controller.dart';
import 'registration_controller.dart';
import 'session_controller.dart';

part 'role_switch_controller.g.dart';

/// The outcome of tapping a role on the post-login mode picker.
enum RoleActionOutcome {
  /// The role is already enrolled and the active session was switched into it — route to its home.
  switched,

  /// The role is NOT yet enrolled — enrolment started; route to that role's profile form (driven by
  /// the returned `profile_token`).
  needsProfile,

  /// Validation/network/other failure — `state.error` carries a user-safe message.
  error,
}

/// UI state for the mode picker / switch affordance.
class RoleSwitchState {
  const RoleSwitchState({this.busy = false, this.error, this.pendingRole});

  final bool busy;
  final String? error;

  /// While [busy], which role the user tapped (so the picker can spinner just that card).
  final RegistrationRole? pendingRole;

  RoleSwitchState copyWith({
    bool? busy,
    Object? error = _unset,
    Object? pendingRole = _unset,
  }) {
    return RoleSwitchState(
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
      pendingRole: identical(pendingRole, _unset)
          ? this.pendingRole
          : pendingRole as RegistrationRole?,
    );
  }
}

const Object _unset = Object();

/// Drives the in-app role switch + add-role flow (one phone = one account that can be BOTH guard +
/// customer). Two actions, both keyed off the user's ENROLLED set (from login / `GET /auth/me`):
///
///  - [switchTo] an ALREADY-enrolled role → `POST /auth/switch-role { role }` mints a NEW access +
///    refresh token pair (active = role). We persist the new pair and swap the session's active role
///    (NO logout — the same account, just a different mode); the router then redirects to the new
///    role's home.
///  - [enrol] in a NOT-yet-enrolled role → `POST /auth/roles { role }` returns a single-use
///    `profile_token` (same shape register issues). We hand it to the registration controller so the
///    existing `/auth/register/{role}` profile form drives the rest → PENDING approval.
///
/// `keepAlive` so the (brief) busy/error state survives the picker rebuilding; a logout has no state
/// to clear here (the session controller owns auth state).
@Riverpod(keepAlive: true)
class RoleSwitchController extends _$RoleSwitchController {
  @override
  RoleSwitchState build() => const RoleSwitchState();

  void clearError() => state = state.copyWith(error: null);

  /// Tap handler for the mode picker: switch into [role] if the account is already enrolled in it,
  /// otherwise start the add-role flow. The picker uses [AuthUser.isEnrolledIn] to render which path
  /// a tap will take (a check vs a "+ add"), but this method re-derives it from the live session so
  /// it is always correct.
  Future<RoleActionOutcome> choose(RegistrationRole role) {
    final user = ref.read(sessionProvider).user;
    if (user != null && user.isEnrolledIn(role.wire)) {
      return switchTo(role);
    }
    return enrol(role);
  }

  /// `POST /auth/switch-role { role }` → swap the session token pair to the new active role.
  /// Re-entrancy-latched. On 409 (`ROLE_NOT_ENROLLED`) the local enrolled set was stale — fall back
  /// to the add-role flow rather than dead-ending.
  Future<RoleActionOutcome> switchTo(RegistrationRole role) async {
    if (state.busy) return RoleActionOutcome.error;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final user = ref.read(sessionProvider).user;
    // Already the active role — nothing to do (the picker shouldn't call this, but be safe).
    if (user != null && user.role == role.wire) {
      return RoleActionOutcome.switched;
    }
    state = state.copyWith(busy: true, error: null, pendingRole: role);
    try {
      final data = await ref
          .read(pguardApiProvider)
          .post('/auth/switch-role', data: {'role': role.wire});
      final map = data as Map<String, dynamic>;
      final access = map['access_token'] as String?;
      final refresh = map['refresh_token'] as String?;
      if (access == null || refresh == null) {
        state = state.copyWith(
            busy: false,
            pendingRole: null,
            error: isThai ? 'สลับโหมดไม่สำเร็จ' : 'Could not switch mode');
        return RoleActionOutcome.error;
      }
      // Persist the NEW pair (the old access token is now superseded; refresh is a fresh family).
      await ref
          .read(appStoreProvider)
          .saveTokens(access: access, refresh: refresh);
      // Trust the new token's `role` claim for the active role (the server is the authority); fall
      // back to the requested role if the claim is somehow absent.
      final activeRole = Jwt.role(access) ?? role.wire;
      ref.read(sessionProvider.notifier).switchActiveRole(activeRole);
      // Deterministically drop the role-scoped caches so each home re-fetches against the NEW token
      // instead of showing the previous role's snapshot. The switch keeps the same user_id and mounts
      // the new home in the same frame the old one unmounts, so autoDispose alone doesn't reliably
      // evict these — the reported "job count / income / rating don't match the account after switch".
      ref.invalidate(
          profileControllerProvider); // greeting name/initials + session.refreshRoles
      ref.invalidate(
          guardJobsControllerProvider); // guard Today-income + Jobs-today + the lists
      ref.invalidate(
          guardRatingsProvider); // whole family → the rating card re-fetches
      ref.invalidate(
          customerHomeControllerProvider); // symmetric guard→customer staleness
      state = state.copyWith(busy: false, pendingRole: null);
      return RoleActionOutcome.switched;
    } on ApiException catch (e) {
      // The enrolled set we trusted was stale (the role isn't actually approved) — start enrolment.
      if (e.statusCode == 409 || e.code == 'ROLE_NOT_ENROLLED') {
        state = state.copyWith(busy: false, pendingRole: null);
        return enrol(role);
      }
      state = state.copyWith(busy: false, pendingRole: null, error: localizeApiError(ref.read(localeControllerProvider) == AppLocale.th, e));
      return RoleActionOutcome.error;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          pendingRole: null,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return RoleActionOutcome.error;
    }
  }

  /// `POST /auth/roles { role }` (enrol a NEW role) → stash the returned single-use `profile_token`
  /// on the registration controller so the existing `/auth/register/{role}` profile form drives the
  /// rest. The session stays AUTHENTICATED (the current role is unaffected) — only on admin approval
  /// does the new role join the switchable set. Re-entrancy-latched. On 409
  /// (`ROLE_ALREADY_ENROLLED`) the set was stale — switch into the role instead.
  Future<RoleActionOutcome> enrol(RegistrationRole role) async {
    if (state.busy) return RoleActionOutcome.error;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    state = state.copyWith(busy: true, error: null, pendingRole: role);
    try {
      final data = await ref
          .read(pguardApiProvider)
          .post('/auth/roles', data: {'role': role.wire});
      final token = (data is Map<String, dynamic>)
          ? data['profile_token'] as String?
          : null;
      if (token == null) {
        state = state.copyWith(
            busy: false,
            pendingRole: null,
            error: isThai ? 'เพิ่มบทบาทไม่สำเร็จ' : 'Could not add role');
        return RoleActionOutcome.error;
      }
      // Hand the profile_token to the registration controller, which owns the profile-form submit
      // (presents it as the Bearer). The user stays authenticated in their CURRENT role meanwhile.
      await ref
          .read(registrationControllerProvider.notifier)
          .beginAddRole(role: role, profileToken: token);
      state = state.copyWith(busy: false, pendingRole: null);
      return RoleActionOutcome.needsProfile;
    } on ApiException catch (e) {
      if (e.statusCode == 409 || e.code == 'ROLE_ALREADY_ENROLLED') {
        // Stale set — the role IS enrolled. Switch into it instead of dead-ending.
        state = state.copyWith(busy: false, pendingRole: null);
        return switchTo(role);
      }
      state = state.copyWith(busy: false, pendingRole: null, error: localizeApiError(ref.read(localeControllerProvider) == AppLocale.th, e));
      return RoleActionOutcome.error;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          pendingRole: null,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return RoleActionOutcome.error;
    }
  }
}
