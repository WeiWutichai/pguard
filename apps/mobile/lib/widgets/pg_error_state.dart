import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/controllers/locale_controller.dart';
import 'primary_button.dart';

/// The hi-fi error state (Mobile - System.html): 96px danger-tinted hero icon tile,
/// 22px heading, muted 14px message, and the green "try again" CTA. Replaces the
/// per-screen ad-hoc `_ErrorBody` patterns so every load failure looks the same and
/// always offers a retry.
class PgErrorState extends ConsumerWidget {
  const PgErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.icon = Icons.cloud_off_outlined,
    this.retryLabel,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  /// When null, falls back to the locale-aware default retry label.
  final String? retryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final label = retryLabel ?? (isThai ? 'ลองอีกครั้ง' : 'Try again');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: PgTokens.colorDangerBg,
                // Design: 28px — nearest token is radius2xl (18); flag for token regen.
                borderRadius: BorderRadius.circular(PgTokens.radius2xl),
              ),
              child: Icon(icon, size: 44, color: PgTokens.colorDanger),
            ),
            const SizedBox(height: PgTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: PgTokens.space2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: PgTokens.colorTextMuted,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: PgTokens.space6),
              PgPrimaryButton(label: label, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
