import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/call_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/models/call.dart';
import '../call_routes.dart';

/// A voice/video call button for an entry-point screen (guard active job / customer live status).
/// Picking audio/video starts an OUTGOING call ([CallController.startOutgoing]) for the booking
/// (the callee is derived server-side) and navigates to the call screen, which reflects the
/// controller's evolving state. Disabled until the booking is callable (active + guard assigned).
class CallEntryButton extends ConsumerWidget {
  const CallEntryButton({
    super.key,
    required this.bookingId,
    this.enabled = true,
  });

  final String bookingId;
  final bool enabled;

  void _start(BuildContext context, WidgetRef ref, CallType type) {
    final router = GoRouter.of(context);
    // Start the call (fire-and-forget) and show the call screen immediately; the screen renders
    // dialing → connecting → active (or ended on failure) from the controller state.
    ref.read(callControllerProvider.notifier).startOutgoing(
          bookingId: bookingId,
          type: type,
        );
    router.push(CallRoutes.outgoing());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return PopupMenuButton<CallType>(
      tooltip: isThai ? 'โทร' : 'Call',
      enabled: enabled,
      onSelected: (type) => _start(context, ref, type),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: CallType.audio,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.call, color: PgTokens.colorPrimary),
            title: Text(isThai ? 'โทรด้วยเสียง' : 'Voice'),
          ),
        ),
        PopupMenuItem(
          value: CallType.video,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.videocam, color: PgTokens.colorPrimary),
            title: Text(isThai ? 'วิดีโอคอล' : 'Video'),
          ),
        ),
      ],
      child: Material(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.call_outlined,
            size: 20,
            color: enabled ? PgTokens.colorPrimary : PgTokens.colorTextFaint,
          ),
        ),
      ),
    );
  }
}
