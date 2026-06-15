import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/registration.dart';

/// Design copy for docs 3/4 differs from the shared model's labels; the model file belongs to
/// another slice, so the design names are applied here as display-only overrides (wire keys and
/// the model stay unchanged).
extension GuardDocDisplay on GuardDocKind {
  String get displayTh => switch (this) {
        GuardDocKind.trainingCert => 'ใบรับรองการฝึก',
        GuardDocKind.criminalCheck => 'ใบตรวจประวัติ',
        _ => labelTh,
      };

  String get displayEn => switch (this) {
        GuardDocKind.trainingCert => 'Training Cert',
        GuardDocKind.criminalCheck => 'Criminal Check',
        _ => labelEn,
      };
}

/// Design `.upl` row: 64×48 thumbnail + name/status column + trailing action, bottom border.
/// The whole row is the tap target for (re)capturing the document.
class GuardDocRow extends StatelessWidget {
  const GuardDocRow({
    super.key,
    required this.kind,
    required this.captured,
    required this.isThai,
    required this.onTap,
    this.expiry,
    this.onSetExpiry,
  });

  final GuardDocKind kind;
  final bool captured;
  final bool isThai;
  final VoidCallback onTap;

  /// The chosen expiry date (all 5 doc kinds carry one — design), or null if not set yet.
  final DateTime? expiry;

  /// Open the expiry date picker for this document. Only surfaced once the doc is captured.
  final VoidCallback? onSetExpiry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PgTokens.space3),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
        ),
        child: Row(
          children: [
            _DocThumb(captured: captured),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThai ? kind.displayTh : kind.displayEn,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // v2 has no image-upload endpoint yet → the captured state honestly reads
                    // "selected", not "uploaded" (only the expiry DATE is sent to the backend).
                    captured
                        ? (isThai ? 'เลือกแล้ว' : 'Selected')
                        : (isThai ? 'ยังไม่อัปโหลด' : 'Not uploaded'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PgTokens.colorTextMuted,
                    ),
                  ),
                  // Expiry capture — only once the doc is selected (metadata only). Its own tap
                  // target, so it doesn't trigger the row's re-capture.
                  if (captured) _expiryButton(),
                ],
              ),
            ),
            if (captured)
              const Icon(Icons.check, size: 18, color: PgTokens.colorSuccess)
            else
              Text(
                isThai ? 'อัปโหลด' : 'Upload',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Inline expiry control under the status line. Its own [InkWell] tap target so picking a date
  /// doesn't trigger the row's re-capture. Prompts to set one (brand ink) or shows the chosen date.
  Widget _expiryButton() {
    final e = expiry;
    final label = e == null
        ? (isThai ? 'ระบุวันหมดอายุ' : 'Set expiry')
        : (isThai ? 'หมดอายุ ${_fmtDate(e)}' : 'Expires ${_fmtDate(e)}');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: onSetExpiry,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined,
                size: 13,
                color: e == null
                    ? PgTokens.colorPrimary
                    : PgTokens.colorTextMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: e == null ? PgTokens.colorPrimary : PgTokens.colorText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

/// 64×48 thumbnail box: captured = green-100→200 gradient + check + safety watermark; empty =
/// strong dashed-style border + plus (Flutter has no native dashed border — solid 2px nearest).
class _DocThumb extends StatelessWidget {
  const _DocThumb({required this.captured});

  final bool captured;

  @override
  Widget build(BuildContext context) {
    if (!captured) {
      return Container(
        width: 64,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          border: Border.all(color: PgTokens.colorBorderStrong, width: 2),
        ),
        child: const Icon(Icons.add, size: 20, color: PgTokens.colorTextFaint),
      );
    }
    return Container(
      width: 64,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PgTokens.colorGreen100, PgTokens.colorGreen200],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -16 * math.pi / 180,
            child: Text(
              'FOR SECURITY USE ONLY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 5.5,
                fontWeight: FontWeight.w700,
                color: PgTokens.colorBrand.withValues(alpha: 0.45),
              ),
            ),
          ),
          const Icon(Icons.check, size: 20, color: PgTokens.colorGreen800),
        ],
      ),
    );
  }
}
