import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A small shared confirm dialog for destructive / consequential actions (accept a job, skip an
/// offer, withdraw from a job). Returns `true` when the user taps confirm, `false`/`null`
/// otherwise. Bilingual: the caller passes already-localized [title]/[message]/[confirmLabel];
/// the cancel label defaults to the active locale via [isThai].
///
/// Matches the house pattern used by the active-job "complete" confirm (an [AlertDialog] with a
/// cancel + confirm pair) so the four accept/decline/cancel/withdraw flows feel consistent.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required bool isThai,
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(cancelLabel ?? (isThai ? 'ยกเลิก' : 'Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: PgTokens.colorDanger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
