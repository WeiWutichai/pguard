import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/active_job_controller.dart';
import '../../../core/controllers/tracking_controller.dart';
import '../../../core/media/photo_capture.dart';
import '../../../core/models/tracking.dart';
import '../../../core/providers.dart';
import '../../../widgets/primary_button.dart';

/// Show the hourly check-in sheet for [hourNumber]; resolves `true` when a report is submitted.
Future<bool?> showCheckInSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String bookingId,
  required int hourNumber,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PgTokens.colorSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
    ),
    builder: (_) =>
        _CheckInSheet(bookingId: bookingId, hourNumber: hourNumber),
  );
}

class _CheckInSheet extends ConsumerStatefulWidget {
  const _CheckInSheet({required this.bookingId, required this.hourNumber});

  final String bookingId;
  final int hourNumber;

  @override
  ConsumerState<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<_CheckInSheet> {
  final TextEditingController _note = TextEditingController();
  CapturedPhoto? _photo;
  GpsSample? _gps; // captured WITH the photo so the coordinate matches the shot
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final photo = await ref.read(photoCaptureServiceProvider).capture();
    if (!mounted) return;
    if (photo == null) {
      setState(() => _error =
          'กล้องไม่พร้อมใช้งานในรุ่นนี้ / Camera unavailable in this build');
      return;
    }
    setState(() {
      _photo = photo;
      // Stamp the GPS fix at the moment of capture (not at submit) for the audit trail.
      _gps = ref.read(trackingControllerProvider).lastSample;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(activeJobControllerProvider(widget.bookingId).notifier)
        .submitCheckIn(
          hourNumber: widget.hourNumber,
          photo: photo,
          gps: _gps,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = ref.read(activeJobControllerProvider(widget.bookingId)).maybeWhen(
              data: (s) => s.error,
              orElse: () => null,
            ) ??
            'ส่งไม่สำเร็จ / Submission failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = ref.watch(trackingControllerProvider).lastSample?.accuracy;
    return Padding(
      padding: EdgeInsets.only(
        left: PgTokens.space4,
        right: PgTokens.space4,
        top: PgTokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + PgTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: PgTokens.colorBorderStrong,
                borderRadius: BorderRadius.circular(PgTokens.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: PgTokens.space4),
          Text('ถึงเวลาเช็คอินรอบที่ ${widget.hourNumber}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            accuracy != null
                ? 'GPS แม่นยำ ${accuracy.toStringAsFixed(0)} ม.'
                : 'แนบพิกัด GPS เมื่อออนไลน์',
            style:
                const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space4),
          _PhotoSlot(photo: _photo, onTap: _busy ? null : _capture),
          const SizedBox(height: PgTokens.space3),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'บันทึกเหตุการณ์ (ไม่บังคับ)…',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: PgTokens.space2),
            Text(_error!, style: const TextStyle(color: PgTokens.colorDanger)),
          ],
          const SizedBox(height: PgTokens.space4),
          PgPrimaryButton(
            label: 'ส่งรายงานรอบนี้ / Submit check-in',
            busy: _busy,
            onPressed: (_photo == null || _busy) ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.photo, required this.onTap});

  final CapturedPhoto? photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = photo != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: PgTokens.colorSunken,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          border: Border.all(
            color: has ? PgTokens.colorPrimary : PgTokens.colorBorderStrong,
            style: has ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(has ? Icons.check_circle : Icons.photo_camera_outlined,
                size: 28,
                color: has ? PgTokens.colorPrimary : PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space1),
            Text(
              has ? 'แนบรูปแล้ว / Photo attached' : 'ถ่ายรูปจุดตรวจ + แนบพิกัด',
              style:
                  const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}
