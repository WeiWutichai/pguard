import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/permissions/location_permission_controller.dart';
import '../../core/permissions/permission_gate.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/primary_button.dart';

/// System screen 3 (`Mobile - System.html`) — the pre-prompt rationale shown BEFORE the OS
/// location dialog, explaining why pguard needs location. The While-using / Always choice is
/// PRESENTATION ONLY: `permission_handler` requests foreground (while-in-use) location regardless
/// — background ("Always") is requested separately once the geolocator-backed GPS source lands.
/// This asks for a REAL permission; it does NOT claim live tracking (the GPS source is still
/// stubbed, so a grant produces no fixes yet — the screen must not overstate that).
enum _LocationScope { whileUsing, always }

class LocationRationaleScreen extends ConsumerStatefulWidget {
  const LocationRationaleScreen({super.key, this.forGuard = false});

  /// Guards on duty default to "Always"; customers to "While using app" (design default).
  final bool forGuard;

  @override
  ConsumerState<LocationRationaleScreen> createState() =>
      _LocationRationaleScreenState();
}

class _LocationRationaleScreenState
    extends ConsumerState<LocationRationaleScreen> {
  late _LocationScope _scope =
      widget.forGuard ? _LocationScope.always : _LocationScope.whileUsing;
  bool _busy = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final state =
        await ref.read(locationPermissionControllerProvider.notifier).request();
    if (!mounted) return;
    setState(() => _busy = false);
    // Permanently denied / restricted → the OS won't prompt again; route to recovery.
    if (state == PgPermissionState.permanentlyDenied ||
        state == PgPermissionState.restricted) {
      context.pushReplacement('/permissions/location/denied');
      return;
    }
    context.pop(state);
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            children: [
              const Spacer(),
              AuthHead(
                icon: const AuthHeadIconTile(icon: Icons.location_on, size: 96),
                title: isThai
                    ? 'เปิดตำแหน่งเพื่อความปลอดภัย'
                    : 'Enable location for safety',
                subtitle: isThai
                    ? 'pguard ใช้ตำแหน่งเพื่อจับคู่เจ้าหน้าที่ใกล้คุณ ติดตามแบบเรียลไทม์ และยืนยันการเช็คอินที่จุดงาน'
                    : 'pguard uses location to match nearby guards, track in real-time, and verify on-site check-ins.',
              ),
              const SizedBox(height: PgTokens.space5),
              _ScopeOption(
                selected: _scope == _LocationScope.whileUsing,
                title: isThai ? 'ขณะใช้งานแอป' : 'While using app',
                subtitle:
                    isThai ? 'แนะนำสำหรับลูกค้า' : 'Recommended for customers',
                onTap: () => setState(() => _scope = _LocationScope.whileUsing),
              ),
              const SizedBox(height: PgTokens.space2),
              _ScopeOption(
                selected: _scope == _LocationScope.always,
                title: isThai ? 'ตลอดเวลา' : 'Always',
                subtitle: isThai
                    ? 'จำเป็นสำหรับเจ้าหน้าที่ที่กำลังทำงาน'
                    : 'Required for guards on duty',
                onTap: () => setState(() => _scope = _LocationScope.always),
              ),
              const Spacer(),
              PgPrimaryButton(
                label: isThai ? 'อนุญาต' : 'Allow',
                busy: _busy,
                onPressed: _allow,
              ),
              const SizedBox(height: PgTokens.space1),
              PgGhostButton(
                label: isThai ? 'ไม่ใช่ตอนนี้' : 'Not now',
                onPressed: _busy ? null : () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One radio "scope" card (design's two stacked radio options).
class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(PgTokens.space4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          border: Border.all(
            color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? PgTokens.colorPrimary
                  : PgTokens.colorTextFaint,
              size: 22,
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
