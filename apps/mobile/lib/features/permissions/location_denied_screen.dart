import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/permissions/location_permission_controller.dart';
import '../../core/permissions/permission_gate.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/primary_button.dart';

/// System screen 4 (`Mobile - System.html`) — recovery when location is PERMANENTLY denied: the
/// OS won't prompt again, so the only path is the device Settings. Re-checks the REAL permission
/// on app-resume (after the user returns from Settings) and pops itself once granted — so the UI
/// reflects what the user actually did, never a stale flag.
class LocationDeniedScreen extends ConsumerStatefulWidget {
  const LocationDeniedScreen({super.key});

  @override
  ConsumerState<LocationDeniedScreen> createState() =>
      _LocationDeniedScreenState();
}

class _LocationDeniedScreenState extends ConsumerState<LocationDeniedScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    final next =
        await ref.read(locationPermissionControllerProvider.notifier).refresh();
    if (mounted && next == PgPermissionState.granted) context.pop(next);
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
                icon: const AuthHeadIconTile(
                  icon: Icons.location_off,
                  size: 96,
                  background: PgTokens.colorDangerBg,
                  foreground: PgTokens.colorDanger,
                ),
                title: isThai ? 'ต้องเปิดสิทธิ์ตำแหน่ง' : 'Location is required',
                subtitle: isThai
                    ? 'แอปต้องใช้ตำแหน่งเพื่อทำงาน กรุณาเปิดในการตั้งค่าของเครื่อง'
                    : 'The app needs location to function. Please enable it in your device settings.',
              ),
              const SizedBox(height: PgTokens.space5),
              _DenyBanner(isThai: isThai),
              const Spacer(),
              PgPrimaryButton(
                label: isThai ? 'เปิดในตั้งค่า' : 'Open Settings',
                onPressed: () => ref
                    .read(locationPermissionControllerProvider.notifier)
                    .openSettings(),
              ),
              const SizedBox(height: PgTokens.space1),
              PgGhostButton(
                label: isThai ? 'ไม่ใช่ตอนนี้' : 'Not now',
                onPressed: () => context.pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's `.deny-banner`: a danger-tinted alert with a warning triangle + the
/// Settings → pguard → Location path.
class _DenyBanner extends StatelessWidget {
  const _DenyBanner({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorDangerBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: PgTokens.colorDanger),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              isThai
                  ? 'สิทธิ์ตำแหน่งถูกปิดอยู่ · เปิดที่ ตั้งค่า → pguard → ตำแหน่ง'
                  : 'Location is off · Settings → pguard → Location',
              style: const TextStyle(
                  fontSize: 12.5, color: PgTokens.colorDanger, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
