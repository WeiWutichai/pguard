import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/auth_models.dart';
import '../models/profile.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';
import 'session_controller.dart';

part 'profile_controller.g.dart';

/// The caller's profile, merged from `GET /v1/auth/me` (user_id + role) and `GET /v1/profile/me`
/// (the customer/guard profile; 404 = not set up yet) plus the locally-stored phone. Editing
/// upserts via `POST /v1/profile/{guard|customer}`. Logout revokes server-side then clears
/// local storage.
@riverpod
class ProfileController extends _$ProfileController {
  @override
  Future<UserProfile> build() async {
    final api = ref.read(pguardApiProvider);
    final session = ref.read(sessionProvider.notifier);
    final me = await api.get('/auth/me') as Map<String, dynamic>;
    // `/auth/me` carries the enrolled-role SET (`roles`) — push it into the session so a role
    // approved AFTER login (the new role joins `user_roles`) starts showing up in the mode picker /
    // switch affordance without a fresh login. No-op when `roles` is absent/empty.
    final roles = AuthUser.rolesFromJson(me['roles']);
    // `pending_roles` = roles with a submitted-but-unapproved profile → the mode picker shows them
    // as "pending approval" instead of re-offering the blank form. Refreshed together with `roles`
    // so an approval (pending → enrolled) and a fresh submit (→ pending) both reflect immediately.
    final pendingRoles = AuthUser.rolesFromJson(me['pending_roles']);
    if (roles.isNotEmpty) {
      session.refreshRoles(roles, pendingRoles: pendingRoles);
    }
    Map<String, dynamic>? profile;
    try {
      profile = await api.get('/profile/me') as Map<String, dynamic>?;
    } on ApiException catch (e) {
      // 404 = the caller hasn't created a profile yet; surface an empty editable one. Other
      // errors are real failures.
      if (e.statusCode != 404) rethrow;
    }
    final phone = await ref.read(appStoreProvider).readPhone();
    return UserProfile.from(me: me, profile: profile, phone: phone);
  }

  /// Upsert editable profile fields (`POST /v1/profile/{guard|customer}`). Only the provided
  /// (non-null) fields are sent. Returns null on success, or a user-safe error message.
  /// NOTE: never pass a masked `accountNumber` back (the server masks it on read).
  Future<String?> save({
    String? fullName,
    String? address,
    String? gender,
    String? dateOfBirth,
    int? yearsOfExperience,
    String? previousWorkplace,
    String? bankName,
    String? accountNumber,
    String? accountName,
  }) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final current = state.valueOrNull;
    if (current == null) return isThai ? 'ยังไม่พร้อม' : 'Not ready';
    try {
      final api = ref.read(pguardApiProvider);
      if (current.isGuard) {
        await api.post('/profile/guard', data: {
          if (gender != null) 'gender': gender,
          if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
          if (yearsOfExperience != null)
            'years_of_experience': yearsOfExperience,
          if (previousWorkplace != null)
            'previous_workplace': previousWorkplace,
          if (bankName != null) 'bank_name': bankName,
          if (accountNumber != null) 'account_number': accountNumber,
          if (accountName != null) 'account_name': accountName,
        });
      } else {
        await api.post('/profile/customer', data: {
          if (fullName != null) 'full_name': fullName,
          if (address != null) 'address': address,
        });
      }
      ref.invalidateSelf();
      await future;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }

  /// `POST /v1/auth/logout` (best-effort server revoke) then clear the local session.
  Future<void> logout() async {
    // Capture refs up-front — this controller is autoDispose and must not touch `ref` after an
    // await (the screen could unmount mid-logout). The captured providers are all keepAlive.
    final store = ref.read(appStoreProvider);
    final api = ref.read(pguardApiProvider);
    final session = ref.read(sessionProvider.notifier);
    final refresh = await store.readRefreshToken();
    try {
      await api.post('/auth/logout',
          data: refresh != null ? {'refresh_token': refresh} : null);
    } catch (_) {
      // Best-effort: even if the server call fails, always clear locally so the user is out.
    }
    await session.logout();
  }
}
