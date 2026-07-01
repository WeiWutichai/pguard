import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/slip_payment_controller.dart';
import '../../../core/media/slip_picker.dart';
import '../../../core/models/booking.dart';
import '../../../core/models/money.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/qr_view.dart';

/// The PromptPay + slip-upload pay panel — shown when the payment provider requires a transfer slip
/// (`PAYMENT_PROVIDER=slip2go`). It renders the SERVER's authoritative PromptPay QR (`qr_payload`),
/// the amount to transfer + our receiving account, and a "ฉันโอนแล้ว / อัปโหลดสลิป" CTA that picks a
/// slip image and posts it to `POST /payments/{id}/slip`. While verifying it shows
/// "กำลังตรวจสอบสลิป…"; on a typed 409 it shows a specific Thai message and lets the customer
/// re-pick. On success it flips to a paid state and the booking proceeds.
class PromptPaySlipPanel extends ConsumerWidget {
  const PromptPaySlipPanel({super.key, required this.bookingId, this.booking});

  final String bookingId;

  /// The live booking — used only to offer a "view live status" jump on success.
  final Booking? booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(slipPaymentControllerProvider(bookingId));

    switch (state.phase) {
      case SlipPhase.loading:
        // The instructions are loading; if the fetch already failed, [error] carries the reason.
        if (state.error != null) {
          return _ErrorPanel(
            message: state.error!,
            isThai: isThai,
            onRetry: () => ref
                .read(slipPaymentControllerProvider(bookingId).notifier)
                .loadInfo(),
          );
        }
        return const Padding(
          padding: EdgeInsets.all(PgTokens.space6),
          child: Center(child: CircularProgressIndicator()),
        );
      case SlipPhase.done:
        return _SlipPaidPanel(booking: booking, isThai: isThai);
      case SlipPhase.ready:
      case SlipPhase.verifying:
        return _TransferPanel(
          bookingId: bookingId,
          state: state,
          isThai: isThai,
        );
    }
  }
}

/// The transfer card: QR + amount + receiving account, the slip CTA, and (while verifying) the
/// "กำลังตรวจสอบสลิป…" state. A typed 409 error renders inline above the CTA.
class _TransferPanel extends ConsumerStatefulWidget {
  const _TransferPanel({
    required this.bookingId,
    required this.state,
    required this.isThai,
  });

  final String bookingId;
  final SlipPaymentState state;
  final bool isThai;

  @override
  ConsumerState<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<_TransferPanel> {
  /// Stable key wrapping the rendered QR so its layer can be captured to a PNG for sharing. Held in
  /// state (not rebuilt) so the boundary survives the panel's rebuilds (e.g. ready ↔ verifying).
  final GlobalKey _qrBoundaryKey = GlobalKey();

  /// Capture the rendered QR [RepaintBoundary] to a PNG in a temp file and hand it to the OS share
  /// sheet, so the customer can save it / open it in a banking app and scan-from-gallery. Guards
  /// against a missing boundary (panel not laid out) and re-checks `mounted` across each await.
  Future<void> _shareQr(int? amountSatang) async {
    final isThai = widget.isThai;
    final messenger = ScaffoldMessenger.of(context);
    String err() => isThai ? 'บันทึก/แชร์ QR ไม่สำเร็จ' : 'Could not save / share the QR';
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        messenger.showSnackBar(SnackBar(content: Text(err())));
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (bytes == null) {
        messenger.showSnackBar(SnackBar(content: Text(err())));
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/promptpay_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      final amount =
          amountSatang != null ? Money.format(amountSatang, decimals: true) : '';
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'PromptPay – ฿$amount'.trimRight(),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(err())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isThai = widget.isThai;
    final info = state.info;
    final verifying = state.phase == SlipPhase.verifying;
    final amountText = info != null
        ? Money.format(info.amountSatang, decimals: true)
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(PgTokens.space5),
          decoration: BoxDecoration(
            color: PgTokens.colorSurface,
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(color: PgTokens.colorBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isThai ? 'สแกนเพื่อโอนผ่าน PromptPay' : 'Scan to pay via PromptPay',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PgTokens.space4),
              Center(
                // Wrap the QR in a keyed RepaintBoundary so its layer can be captured to a PNG and
                // shared/saved (the white padding is included → a clean scannable image with a quiet
                // zone). The QR encoding stays pure inside [QrView].
                child: RepaintBoundary(
                  key: _qrBoundaryKey,
                  child: Container(
                    padding: const EdgeInsets.all(PgTokens.space3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                      border: Border.all(color: PgTokens.colorBorder),
                    ),
                    child: QrView(data: info?.qrPayload ?? '', size: 224),
                  ),
                ),
              ),
              const SizedBox(height: PgTokens.space3),
              // Save / share the QR image so the customer can open a banking app and scan from the
              // gallery. Secondary (outlined) styling so it never competes with the primary
              // "ฉันโอนแล้ว / อัปโหลดสลิป" CTA below. Disabled until the QR payload has loaded.
              OutlinedButton.icon(
                onPressed: (info != null && info.qrPayload.isNotEmpty)
                    ? () => _shareQr(info.amountSatang)
                    : null,
                icon: const Icon(Icons.ios_share, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PgTokens.colorGreen800,
                  side: const BorderSide(color: PgTokens.colorGreen800),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                  ),
                  textStyle: const TextStyle(
                      fontFamily: 'IBMPlexSansThai',
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                label: Text(isThai ? 'บันทึก / แชร์ QR' : 'Save / Share QR'),
              ),
              const SizedBox(height: PgTokens.space4),
              _InfoRow(
                label: isThai ? 'ยอดที่ต้องโอน' : 'Amount to transfer',
                value: amountText,
                emphasise: true,
              ),
              const SizedBox(height: PgTokens.space2),
              _InfoRow(
                label: isThai ? 'บัญชีรับเงิน' : 'Receiving account',
                value: info?.receivingAccount ?? '—',
              ),
              const SizedBox(height: PgTokens.space3),
              Text(
                isThai
                    ? 'โอนผ่านแอปธนาคารตามยอดด้านบน แล้วกด “ฉันโอนแล้ว” เพื่อแนบสลิป'
                    : 'Transfer the amount above in your banking app, then tap “I’ve paid” to '
                        'upload the slip.',
                style: const TextStyle(
                    fontSize: 11.5, color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: PgTokens.space4),
        if (verifying)
          _VerifyingPanel(isThai: isThai)
        else ...[
          if (state.error != null) ...[
            _ErrorBanner(message: state.error!),
            const SizedBox(height: PgTokens.space3),
          ],
          PgPrimaryButton(
            label: isThai ? 'ฉันโอนแล้ว / อัปโหลดสลิป' : 'I’ve paid / upload slip',
            onPressed: () => _pickSlip(context, ref),
          ),
        ],
      ],
    );
  }

  /// Offer gallery (a banking-app screenshot) or camera (a printed receipt), then upload.
  Future<void> _pickSlip(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<SlipSource>(
      context: context,
      backgroundColor: PgTokens.colorSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: PgTokens.space2),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: PgTokens.colorGreen800),
              title: Text(
                  widget.isThai ? 'เลือกจากคลังรูป' : 'Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(SlipSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: PgTokens.colorGreen800),
              title: Text(widget.isThai ? 'ถ่ายรูปสลิป' : 'Take a photo'),
              onTap: () => Navigator.of(ctx).pop(SlipSource.camera),
            ),
            const SizedBox(height: PgTokens.space2),
          ],
        ),
      ),
    );
    if (source == null) return;
    await ref
        .read(slipPaymentControllerProvider(widget.bookingId).notifier)
        .pickAndUpload(source);
  }
}

/// The "กำลังตรวจสอบสลิป…" verifying state — a spinner + label, no CTA (the upload is in flight).
class _VerifyingPanel extends StatelessWidget {
  const _VerifyingPanel({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorAmber50,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorAmber200),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: PgTokens.colorAmber700),
          ),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Text(
              isThai ? 'กำลังตรวจสอบสลิป…' : 'Verifying your slip…',
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The PaymentSuccess state after a slip verifies: the booking proceeds; offers a live-status jump.
class _SlipPaidPanel extends StatelessWidget {
  const _SlipPaidPanel({required this.booking, required this.isThai});

  final Booking? booking;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space5),
      decoration: BoxDecoration(
        color: PgTokens.colorSuccessBg,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child:
                Icon(Icons.check_circle, size: 48, color: PgTokens.colorSuccess),
          ),
          const SizedBox(height: PgTokens.space3),
          Text(
            isThai ? 'ตรวจสอบสลิปสำเร็จ' : 'Slip verified',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: PgTokens.colorGreen900),
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai
                ? 'ชำระเงินสำเร็จ — รอเจ้าหน้าที่เริ่มเดินทาง'
                : 'Payment received — waiting for the guard to set off',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: PgTokens.colorText),
          ),
          if (booking != null) ...[
            const SizedBox(height: PgTokens.space4),
            PgPrimaryButton(
              label: isThai ? 'ดูสถานะงาน' : 'View live status',
              // Root on home then push live so back returns to the dashboard — a bare `go` made the
              // live screen a lone root with nothing to pop (stranded the customer on a dead job).
              onPressed: () {
                context.go('/home/customer');
                context.push('/booking/${booking!.id}/live');
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A label/value row in the transfer card.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted)),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasise ? 17 : 14,
            fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
            color: emphasise ? PgTokens.colorGreen800 : PgTokens.colorText,
          ),
        ),
      ],
    );
  }
}

/// An inline typed-error banner (e.g. "สลิปนี้ถูกใช้แล้ว") above the re-pick CTA.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorDangerBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: PgTokens.colorDanger),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorDanger)),
          ),
        ],
      ),
    );
  }
}

/// A full-panel error (the instructions failed to load) with a retry.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.isThai,
    required this.onRetry,
  });

  final String message;
  final bool isThai;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space5),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline,
              size: 32, color: PgTokens.colorDanger),
          const SizedBox(height: PgTokens.space3),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: PgTokens.space4),
          PgPrimaryButton(
            label: isThai ? 'ลองอีกครั้ง' : 'Try again',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
