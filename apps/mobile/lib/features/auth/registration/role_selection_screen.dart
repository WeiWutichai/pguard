import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/registration_controller.dart';
import '../../../core/controllers/role_switch_controller.dart';
import '../../../core/controllers/session_controller.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/models/registration.dart';
import '../../profile/widgets/lang_segmented.dart';

/// Role chooser — TWO modes, switched by the session status:
///
///  - **Onboarding** (unauthenticated / onboardingRole, the original flow): tap a role to register
///    the account (`POST /auth/register`) — on 202 go to the matching profile form; a 409
///    ("already registered") logs the returning user in and the router redirects to their dashboard.
///
///  - **Mode picker** (AUTHENTICATED, one phone = one account that can be BOTH guard + customer): the
///    "เลือกโหมด" screen. Each role is marked ENROLLED or not. Tapping an enrolled role calls
///    `POST /auth/switch-role` and routes to that role's home WITHOUT logging out; tapping a
///    not-yet-enrolled role starts the ADD-ROLE flow (`POST /auth/roles` → that role's profile form
///    → pending). A back/close returns to the CURRENT role's home (never strands the user).
///
/// Design (stitch role-chooser): a top-right TH|EN toggle, a hero illustration (guard + protected
/// home), the centered headline + subtitle, then two `.role-card`s — Guard FIRST with a green-900
/// shield tile, then "จ้าง รปภ" with an amber person-search tile — each a border-only card with a
/// 56×56 icon tile + trailing chevron, and a copyright footer.
class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final session = ref.watch(sessionProvider);
    // AUTHENTICATED → the in-app mode picker (switch / add role, no logout). Otherwise the original
    // onboarding registration chooser.
    final picker = session.status == SessionStatus.authenticated;

    if (picker) {
      return _ModePicker(user: session.user, isThai: isThai);
    }
    return _OnboardingChooser(isThai: isThai);
  }
}

/// The AUTHENTICATED mode picker ("เลือกโหมด"). Drives [RoleSwitchController]: an enrolled role →
/// switch-role → that home; a not-yet-enrolled role → add-role profile flow. A back/close returns to
/// the current role's home.
class _ModePicker extends ConsumerWidget {
  const _ModePicker({required this.user, required this.isThai});

  final AuthUser? user;
  final bool isThai;

  String _homeFor(String role) =>
      role == 'guard' ? '/home/guard' : '/home/customer';

  Future<void> _tap(
      BuildContext context, WidgetRef ref, RegistrationRole role) async {
    final outcome =
        await ref.read(roleSwitchControllerProvider.notifier).choose(role);
    if (!context.mounted) return;
    switch (outcome) {
      case RoleActionOutcome.switched:
        // Active role swapped (no logout); route to the new role's home.
        context.go(_homeFor(role.wire));
      case RoleActionOutcome.needsProfile:
        // Add-role: the registration controller holds the profile_token; open that role's form.
        context.push(
            role.isGuard ? '/auth/register/guard' : '/auth/register/customer');
      case RoleActionOutcome.error:
        break; // state.error is rendered below
    }
  }

  void _close(BuildContext context) {
    // Never strand the user: go back to their CURRENT role's home.
    context.go(_homeFor(user?.role ?? 'customer'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roleSwitchControllerProvider);
    final activeRole = user?.role;
    bool enrolled(RegistrationRole r) => user?.isEnrolledIn(r.wire) == true;
    bool pending(RegistrationRole r) => user?.isPendingIn(r.wire) == true;
    // Refresh /auth/me (auto-dispose → re-fetches on each open) so a role SUBMITTED since login shows
    // as pending here. Its `session.refreshRoles(roles, pendingRoles: …)` re-emits the session, which
    // rebuilds this picker with the fresh pending set.
    //
    // The PIN-login response only carries the ENROLLED set, not the PENDING one, so on a returning
    // login the session's pending set is empty until this /auth/me lands. Gate the cards on that
    // first load: without it a pending role renders as a normal (tappable) card for a beat, and a tap
    // in that window re-opens the registration form / bounces to a status page instead of just showing
    // "รอตรวจ". Once loaded, the pending card stays disabled by `pending(...)` below.
    final rolesLoading = ref.watch(profileControllerProvider).isLoading;

    return PopScope(
      // Intercept the system back so it returns to the current home (not the auth stack).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close(context);
      },
      child: Scaffold(
        backgroundColor: PgTokens.colorBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: PgTokens.space3),
                Row(
                  children: [
                    // A close affordance back to the current home (so "switch mode" is escapable).
                    IconButton(
                      onPressed: state.busy ? null : () => _close(context),
                      icon: const Icon(Icons.close),
                      tooltip: isThai ? 'ปิด' : 'Close',
                      color: PgTokens.colorTextMuted,
                    ),
                    const Spacer(),
                    LangSegmented(
                      value: ref.watch(localeControllerProvider),
                      onChanged: (l) => ref
                          .read(localeControllerProvider.notifier)
                          .setLocale(l),
                    ),
                  ],
                ),
                const SizedBox(height: PgTokens.space2),
                Image.asset('assets/images/role_hero.png',
                    height: 180, fit: BoxFit.contain),
                const SizedBox(height: PgTokens.space5),
                Text(
                  isThai ? 'เลือกโหมด' : 'Choose mode',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: PgTokens.colorTextStrong,
                  ),
                ),
                const SizedBox(height: PgTokens.space2),
                Text(
                  isThai
                      ? 'สลับระหว่างเจ้าหน้าที่และลูกค้า'
                      : 'Switch between guard and customer',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PgTokens.colorTextMuted),
                ),
                const SizedBox(height: PgTokens.space6),
                _RoleCard(
                  icon: Icons.shield_outlined,
                  iconBg: PgTokens.colorGreen900,
                  iconFg: Colors.white,
                  title: isThai ? 'เจ้าหน้าที่ รปภ.' : 'Security Guard',
                  desc: _modeDesc(RegistrationRole.guard),
                  // A pending role is NOT tappable → it can't re-open the registration form. Also
                  // gated while the pending set is still loading (see rolesLoading above).
                  enabled: !state.busy &&
                      !rolesLoading &&
                      !pending(RegistrationRole.guard),
                  loading:
                      state.busy && state.pendingRole == RegistrationRole.guard,
                  active: activeRole == 'guard',
                  enrolled: enrolled(RegistrationRole.guard),
                  pending: pending(RegistrationRole.guard),
                  isThai: isThai,
                  onTap: () => _tap(context, ref, RegistrationRole.guard),
                ),
                const SizedBox(height: 14),
                _RoleCard(
                  icon: Icons.person_search_outlined,
                  iconBg: PgTokens.colorAmber100,
                  iconFg: PgTokens.colorAmber700,
                  title: isThai ? 'จ้าง รปภ' : 'Hire a Guard',
                  desc: _modeDesc(RegistrationRole.customer),
                  enabled: !state.busy &&
                      !rolesLoading &&
                      !pending(RegistrationRole.customer),
                  loading: state.busy &&
                      state.pendingRole == RegistrationRole.customer,
                  active: activeRole == 'customer',
                  enrolled: enrolled(RegistrationRole.customer),
                  pending: pending(RegistrationRole.customer),
                  isThai: isThai,
                  onTap: () => _tap(context, ref, RegistrationRole.customer),
                ),
                const SizedBox(height: PgTokens.space6),
                if (state.error != null && !state.busy)
                  Text(
                    state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: PgTokens.space5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _modeDesc(RegistrationRole role) {
    if (user?.role == role.wire) {
      return isThai ? 'โหมดปัจจุบัน' : 'Current mode';
    }
    if (user?.isEnrolledIn(role.wire) == true) {
      return isThai ? 'แตะเพื่อสลับไปโหมดนี้' : 'Tap to switch to this mode';
    }
    if (user?.isPendingIn(role.wire) == true) {
      return isThai
          ? 'ส่งข้อมูลแล้ว — รอแอดมินอนุมัติ'
          : 'Submitted — awaiting admin approval';
    }
    return isThai ? 'แตะเพื่อเพิ่มบทบาทนี้' : 'Tap to add this role';
  }
}

/// The original onboarding registration chooser (unchanged behavior — single-role path).
class _OnboardingChooser extends ConsumerWidget {
  const _OnboardingChooser({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationControllerProvider);
    final ctrl = ref.read(registrationControllerProvider.notifier);

    Future<void> choose(RegistrationRole role) async {
      ctrl.selectRole(role);
      final outcome = await ctrl.register();
      if (!context.mounted) return;
      if (outcome == RegisterOutcome.needsProfile) {
        context.push(
            role.isGuard ? '/auth/register/guard' : '/auth/register/customer');
        return;
      }
      if (outcome == RegisterOutcome.needsPinLogin) {
        // Existing account, but the PIN they set didn't match — the controller dropped the session
        // to `returning`. Send them to PIN-login to enter their REAL PIN (the returning `/auth/*`
        // redirect allows role-select to linger, so navigate explicitly).
        context.go('/login/pin');
        return;
      }
      if (outcome == RegisterOutcome.loggedIn) {
        // The phone already has an account (409 → logged in). If the user picked a role this account
        // does NOT hold yet (e.g. a customer-only phone where they tapped "guard"), take them
        // STRAIGHT into ADDING that role — its BLANK registration form — instead of dropping them on
        // the mode picker, which shows their EXISTING role as "current mode" and reads as "I chose
        // guard but it's still customer data". If the account already holds the picked role, the
        // router lands them on the right home as usual.
        final user = ref.read(sessionProvider).user;
        if (user != null && !user.isEnrolledIn(role.wire)) {
          final add = await ref
              .read(roleSwitchControllerProvider.notifier)
              .choose(role);
          if (!context.mounted) return;
          switch (add) {
            case RoleActionOutcome.needsProfile:
              // Enrolled → open that role's fresh profile form (the add-role flow).
              context.push(role.isGuard
                  ? '/auth/register/guard'
                  : '/auth/register/customer');
            case RoleActionOutcome.switched:
              // Already enrolled after all (stale set) → just land on that role's home.
              context.go(role.isGuard ? '/home/guard' : '/home/customer');
            case RoleActionOutcome.error:
              // Enrol failed → fall back to the mode picker so the user isn't stranded.
              context.go('/auth/role');
          }
        }
      }
      // error → state.error is rendered below; the user can retry.
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space3),
              // Pre-login language choice, top-right (design `.seg-sm`).
              Align(
                alignment: Alignment.centerRight,
                child: LangSegmented(
                  value: ref.watch(localeControllerProvider),
                  onChanged: (l) =>
                      ref.read(localeControllerProvider.notifier).setLocale(l),
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              // Hero illustration — a guard presenting the app over a protected home.
              Image.asset('assets/images/role_hero.png',
                  height: 200, fit: BoxFit.contain),
              const SizedBox(height: PgTokens.space5),
              Text(
                isThai ? 'คุณคือใคร?' : 'Who are you?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorTextStrong,
                ),
              ),
              const SizedBox(height: PgTokens.space2),
              Text(
                isThai ? 'เลือกบทบาทเพื่อเริ่มต้น' : 'Pick a role to continue',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              // Guard FIRST (green-900 shield tile).
              _RoleCard(
                icon: Icons.shield_outlined,
                iconBg: PgTokens.colorGreen900,
                iconFg: Colors.white,
                title: isThai ? 'เจ้าหน้าที่ รปภ.' : 'Security Guard',
                desc: isThai
                    ? 'สำหรับเจ้าหน้าที่เพื่อเข้าใช้งานระบบ'
                    : 'For guards to access the system',
                enabled: !state.busy,
                isThai: isThai,
                onTap: () => choose(RegistrationRole.guard),
              ),
              const SizedBox(height: 14),
              // Customer second — "hire a guard" (amber person-search tile).
              _RoleCard(
                icon: Icons.person_search_outlined,
                iconBg: PgTokens.colorAmber100,
                iconFg: PgTokens.colorAmber700,
                title: isThai ? 'จ้าง รปภ' : 'Hire a Guard',
                desc: isThai
                    ? 'จ้างเจ้าหน้าที่รักษาความปลอดภัยระดับมืออาชีพ'
                    : 'Hire professional security guards',
                enabled: !state.busy,
                isThai: isThai,
                onTap: () => choose(RegistrationRole.customer),
              ),
              const SizedBox(height: PgTokens.space6),
              if (state.busy)
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (state.error != null && !state.busy)
                Text(
                  state.error!,
                  style: const TextStyle(color: PgTokens.colorDanger),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: PgTokens.space7),
              const Text(
                '© 2023 Security Platform System',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: PgTokens.colorTextFaint),
              ),
              const SizedBox(height: PgTokens.space5),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.role-card`: a border-only card (1.5px, radius 20, padding 22, gap 16) with a 56×56 colored
/// icon tile (radius 16) + title (.rt 18/w600) and description (.rd 13/muted). In the mode picker it
/// can also show an "active"/"enrolled" badge and a per-card spinner while switching.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.desc,
    required this.enabled,
    required this.onTap,
    required this.isThai,
    this.loading = false,
    this.active = false,
    this.enrolled = false,
    this.pending = false,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String desc;
  final bool enabled;
  final VoidCallback onTap;
  final bool isThai;

  /// Mode-picker only: a per-card spinner while this role's switch/add is in flight.
  final bool loading;

  /// Mode-picker only: this is the currently-active role (badge "ปัจจุบัน").
  final bool active;

  /// Mode-picker only: the account is enrolled in this role (badge "พร้อมใช้").
  final bool enrolled;

  /// Mode-picker only: this role has a SUBMITTED-but-unapproved profile (badge "รอตรวจ"). The card
  /// is passed `enabled: false` so it can't re-open the registration form — it just shows status.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? PgTokens.colorPrimary : PgTokens.colorBorder,
              width: active ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: iconFg),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: PgTokens.colorTextStrong)),
                        ),
                        if (active) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: isThai ? 'ปัจจุบัน' : 'Current',
                            fg: PgTokens.colorPrimary,
                            bg: PgTokens.colorGreen100,
                          ),
                        ] else if (enrolled) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: isThai ? 'พร้อมใช้' : 'Ready',
                            fg: PgTokens.colorTextMuted,
                            bg: PgTokens.colorSunken,
                          ),
                        ] else if (pending) ...[
                          const SizedBox(width: 8),
                          _Badge(
                            label: isThai ? 'รอตรวจ' : 'Pending',
                            fg: PgTokens.colorAmber700,
                            bg: PgTokens.colorAmber100,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(desc,
                        style: const TextStyle(
                            color: PgTokens.colorTextMuted,
                            fontSize: 13,
                            height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                    pending
                        ? Icons.hourglass_empty
                        : (enrolled || active
                            ? Icons.chevron_right
                            : Icons.add),
                    color: PgTokens.colorTextFaint,
                    size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: PgTokens.space2, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
