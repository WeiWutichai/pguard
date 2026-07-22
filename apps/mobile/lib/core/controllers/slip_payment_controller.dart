import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/image_mime.dart';
import '../media/slip_picker.dart';
import '../models/payment.dart';
import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'booking_status_controller.dart';
import 'locale_controller.dart';

part 'slip_payment_controller.g.dart';

/// Where the customer is in the PromptPay + slip flow. Pure data the [SlipPaymentScreen] renders.
enum SlipPhase {
  /// Fetching the transfer instructions (`GET /payments/{id}/promptpay`).
  loading,

  /// Showing the QR + amount + receiving account, waiting for the customer to transfer + upload.
  ready,

  /// A slip upload (`POST /payments/{id}/slip`) is in flight — "กำลังตรวจสอบสลิป…".
  verifying,

  /// The slip verified and the payment is settled — the booking can proceed.
  done,
}

/// The PromptPay transfer instructions, parsed from `GET /payments/{id}/promptpay`. The
/// [qrPayload] is the SERVER's authoritative EMVCo string — the client renders it and NEVER
/// rebuilds it, so the amount + receiver can't drift.
class PromptPay {
  const PromptPay({
    required this.amount,
    required this.amountSatang,
    required this.receivingAccount,
    required this.qrPayload,
  });

  /// Server-side estimate as an exact decimal string ("2000.00").
  final String amount;

  /// The estimate in satang (×100), derived server-side from the Decimal (never a float).
  final int amountSatang;

  /// OUR receiving PromptPay account, formatted for display ("081-234-5678").
  final String receivingAccount;

  /// The authoritative EMVCo PromptPay QR payload (render as a QR; do NOT rebuild).
  final String qrPayload;

  factory PromptPay.fromJson(Map<String, dynamic> json) => PromptPay(
        amount: json['amount'] as String? ?? '',
        amountSatang: (json['amount_satang'] as num?)?.toInt() ?? 0,
        receivingAccount: json['receiving_account'] as String? ?? '',
        qrPayload: json['qr_payload'] as String? ?? '',
      );
}

/// The full slip-pay state the screen renders.
class SlipPaymentState {
  const SlipPaymentState({
    this.phase = SlipPhase.loading,
    this.info,
    this.error,
    this.payment,
  });

  final SlipPhase phase;

  /// The transfer instructions once loaded (null while [SlipPhase.loading]).
  final PromptPay? info;

  /// A localized, user-safe failure message for the last attempt (typed 409 → a specific Thai
  /// message), else null. Set in the [SlipPhase.ready] phase so the customer can re-pick a slip.
  final String? error;

  /// The settled payment once a slip verifies (status `completed`).
  final Payment? payment;

  bool get isDone => phase == SlipPhase.done;

  SlipPaymentState copyWith({
    SlipPhase? phase,
    PromptPay? info,
    Object? error = _unset,
    Payment? payment,
  }) =>
      SlipPaymentState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        error: identical(error, _unset) ? this.error : error as String?,
        payment: payment ?? this.payment,
      );
}

const Object _unset = Object();

/// Drives the PromptPay + slip-upload pay step for ONE booking (the `bookingId` family arg, so two
/// bookings never share state). Used ONLY when the payment provider requires a slip
/// (`PAYMENT_PROVIDER=slip2go`); under the simulated default the customer pays via the existing
/// `POST /payments` path ([PaymentController]) and never reaches here.
///
/// Endpoints (contracts/openapi/payment.yaml):
///  - `GET  /payments/{id}/promptpay` — own-only; the server-computed estimate + receiving account
///    + the authoritative EMVCo `qr_payload`. `{id}` is the BOOKING id.
///  - `POST /payments/{id}/slip` — multipart `file` (the transfer-slip image); on success the
///    payment is settled (same `payment.completed` event that un-gates `en_route`). Typed 409s:
///    `SLIP_VERIFY_FAILED` / `SLIP_AMOUNT_TOO_LOW` / `SLIP_WRONG_RECEIVER` / `SLIP_DUPLICATE`.
@riverpod
class SlipPaymentController extends _$SlipPaymentController {
  bool _disposed = false;

  @override
  SlipPaymentState build(String bookingId) {
    ref.onDispose(() => _disposed = true);
    // Kick off the transfer-instructions fetch; the screen renders the loading phase until it lands.
    Future.microtask(loadInfo);
    return const SlipPaymentState();
  }

  bool get _isThai => ref.read(localeControllerProvider) == AppLocale.th;

  /// Fetch the PromptPay instructions. On success → [SlipPhase.ready] with the QR/amount/account;
  /// on failure stays loading with a banner error (the screen offers a retry).
  Future<void> loadInfo() async {
    try {
      final data = await ref
          .read(pguardApiProvider)
          .get('/payments/$bookingId/promptpay');
      if (_disposed) return;
      final info = PromptPay.fromJson(data as Map<String, dynamic>);
      state = state.copyWith(phase: SlipPhase.ready, info: info, error: null);
    } on ApiException catch (e) {
      if (_disposed) return;
      state = state.copyWith(error: localizeApiError(ref.read(localeControllerProvider) == AppLocale.th, e));
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
          error: _isThai ? 'โหลดข้อมูลการชำระไม่สำเร็จ' : 'Could not load payment details');
    }
  }

  /// Pick a slip image and upload it. Returns `true` if the slip verified (the flow proceeds).
  /// On a typed 409 it sets a specific localized [SlipPaymentState.error] and returns to
  /// [SlipPhase.ready] so the customer can re-pick. A cancelled pick is a no-op (returns false).
  Future<bool> pickAndUpload(SlipSource source) async {
    final path = await ref.read(slipPickerProvider).pick(source);
    if (path == null) return false; // user cancelled the picker
    return uploadSlip(path);
  }

  /// Upload an already-picked slip image at [filePath] (the seam the screen/tests drive directly).
  /// Multiparts `file` with a magic-byte MIME so the server's content-type gate always matches.
  Future<bool> uploadSlip(String filePath) async {
    if (state.phase == SlipPhase.verifying) return false; // ignore a double-tap
    state = state.copyWith(phase: SlipPhase.verifying, error: null);
    try {
      // Declare the MIME from the file's ACTUAL magic bytes (image_picker may re-encode to JPEG
      // while keeping the source extension), so the server's magic-byte check always matches.
      final mime = detectImageMime(await readImageHead(filePath, 12)) ?? 'image/jpeg';
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final data =
          await ref.read(pguardApiProvider).post('/payments/$bookingId/slip', data: form);
      if (_disposed) return true;
      final payment =
          data is Map<String, dynamic> ? Payment.fromJson(data) : null;
      state = state.copyWith(
          phase: SlipPhase.done, payment: payment, error: null);
      // Optimistically mark the LIVE booking paid the instant the slip clears — so the pay banner
      // disappears immediately and never flickers back on a stale snapshot (same monotonic paid
      // flag the simulated path uses). Only touch the live controller when it is already alive.
      if (ref.exists(bookingStatusControllerProvider(bookingId))) {
        ref.read(bookingStatusControllerProvider(bookingId).notifier).markPaid();
      }
      return true;
    } on ApiException catch (e) {
      if (_disposed) return false;
      state = state.copyWith(phase: SlipPhase.ready, error: _slipError(e));
      return false;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        phase: SlipPhase.ready,
        error: _isThai ? 'อัปโหลดสลิปไม่สำเร็จ' : 'Slip upload failed',
      );
      return false;
    }
  }

  /// Map the server's machine-readable slip `error.code` to a clear, specific bilingual message.
  /// Branch on the CODE (not the message). Falls back to the server's own text for anything
  /// unrecognised (e.g. a non-image rejection), which is already user-safe.
  String _slipError(ApiException e) {
    final thai = _isThai;
    switch (e.code) {
      case 'SLIP_VERIFY_FAILED':
        return thai
            ? 'สลิปไม่ถูกต้อง — ตรวจไม่พบการโอน กรุณาอัปโหลดสลิปที่ชัดเจน'
            : 'Slip could not be verified — please upload a clear transfer slip';
      case 'SLIP_AMOUNT_TOO_LOW':
        return thai
            ? 'ยอดโอนไม่พอ — กรุณาโอนตามยอดที่กำหนดแล้วอัปโหลดสลิปใหม่'
            : 'The transferred amount is too low — please transfer the exact amount';
      case 'SLIP_WRONG_RECEIVER':
        return thai
            ? 'โอนผิดบัญชี — กรุณาโอนไปยังบัญชีที่แสดงแล้วอัปโหลดสลิปใหม่'
            : 'Paid to the wrong account — please transfer to the account shown';
      case 'SLIP_DUPLICATE':
        return thai
            ? 'สลิปนี้ถูกใช้แล้ว — กรุณาใช้สลิปการโอนใบใหม่'
            : 'This slip has already been used — please use a new transfer slip';
      case 'SLIP_REQUIRED':
        return thai
            ? 'กรุณาแนบสลิปการโอน'
            : 'Please attach a transfer slip';
      default:
        return e.message;
    }
  }
}
