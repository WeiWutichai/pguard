import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/models/progress_report.dart';
import 'pg_network_image.dart';

/// Opens a full-screen viewer for one submitted hourly check-in [report]: the guard's photo
/// (pinch-to-zoom), the capture time, the GPS coordinate + accuracy, and the optional note.
///
/// The [report.photoUrl] is a FRESH presigned GET URL (TTL ~1h) the server signs per read — so a
/// long-open viewer can outlive it; the image's [Image.network] error builder degrades to a
/// "reopen" hint rather than a broken icon. Shared by the guard active-job timeline AND the
/// customer live-status timeline so both surfaces open a reported check-in the same way.
Future<void> showProgressReportViewer(
  BuildContext context, {
  required ProgressReport report,
  required bool isThai,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ProgressReportViewer(report: report, isThai: isThai),
  );
}

class _ProgressReportViewer extends StatelessWidget {
  const _ProgressReportViewer({required this.report, required this.isThai});

  final ProgressReport report;
  final bool isThai;

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get _timeLabel {
    final l = report.createdAt.toLocal();
    return '${l.day}/${_two(l.month)} ${_two(l.hour)}:${_two(l.minute)}';
  }

  String get _hourLabel => report.hourNumber == 1
      ? (isThai ? 'เริ่มงาน · เช็คอินจุดนัด' : 'Start · check in')
      : (isThai
          ? 'ตรวจรอบที่ ${report.hourNumber - 1}'
          : 'Round ${report.hourNumber - 1} check-in');

  @override
  Widget build(BuildContext context) {
    final lat = report.lat;
    final lng = report.lng;
    final hasGps = lat != null && lng != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(PgTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Close affordance, right-aligned over the dark scrim.
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: isThai ? 'ปิด' : 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PgTokens.radius2xl),
              child: Container(
                color: PgTokens.colorSurface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                        child: _Photo(url: report.photoUrl, isThai: isThai)),
                    Padding(
                      padding: const EdgeInsets.all(PgTokens.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hourLabel,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: PgTokens.space2),
                          _MetaRow(
                            icon: Icons.schedule,
                            text: _timeLabel,
                          ),
                          if (hasGps) ...[
                            const SizedBox(height: PgTokens.space1),
                            _MetaRow(
                              icon: Icons.place_outlined,
                              text: report.accuracyM != null
                                  ? (isThai
                                      ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} · แม่นยำ ${report.accuracyM!.toStringAsFixed(0)} ม.'
                                      : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} · ±${report.accuracyM!.toStringAsFixed(0)} m')
                                  : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                            ),
                          ],
                          if (report.note != null &&
                              report.note!.trim().isNotEmpty) ...[
                            const SizedBox(height: PgTokens.space3),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(PgTokens.space3),
                              decoration: BoxDecoration(
                                color: PgTokens.colorSunken,
                                borderRadius:
                                    BorderRadius.circular(PgTokens.radiusLg),
                              ),
                              child: Text(
                                report.note!.trim(),
                                style: const TextStyle(
                                    fontSize: 13.5, color: PgTokens.colorText),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The zoomable check-in photo. Mirrors chat_bubble's [Image.network] degrade: a presigned URL
/// can expire, so a load failure shows a "reopen" hint instead of a broken-image glyph.
class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.isThai});

  final String url;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _expired(isThai);
    }
    return InteractiveViewer(
      maxScale: 4,
      // Full-screen zoomable → keep full resolution (downsize:false); disk cache still applies.
      child: PgNetworkImage(
        url: url,
        fit: BoxFit.contain,
        downsize: false,
        placeholder: const SizedBox(
          height: 220,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: _expired(isThai),
      ),
    );
  }

  static Widget _expired(bool isThai) => Padding(
        padding: const EdgeInsets.symmetric(
            vertical: PgTokens.space8, horizontal: PgTokens.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 28, color: PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space2),
            Text(
              isThai
                  ? 'รูปหมดอายุ — เปิดใหม่อีกครั้ง'
                  : 'Image expired — reopen',
              style:
                  const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
            ),
          ],
        ),
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: PgTokens.colorTextMuted),
        const SizedBox(width: PgTokens.space2),
        Expanded(
          child: Text(
            text,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ),
      ],
    );
  }
}
