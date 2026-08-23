import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'support_ticket_controller.g.dart';

/// The two ticket buckets the Help form offers. `wire` is the exact string the backend's
/// `CHECK (kind IN ('problem','feedback'))` accepts — never localize this.
enum SupportTicketKind {
  problem('problem'),
  feedback('feedback');

  const SupportTicketKind(this.wire);
  final String wire;
}

/// Outcome of a support-ticket submit.
enum SupportTicketOutcome {
  /// 200 — the ticket was filed.
  sent,

  /// Validation/network/other failure — `state.error` carries a user-safe message.
  error,
}

const Object _unset = Object();

/// The largest message the backend accepts (`MAX_SUPPORT_TICKET_MESSAGE_LEN`). Mirrored here so
/// the field can cap input BEFORE the round-trip (the server still validates → typed 400).
const int kMaxSupportTicketMessageLen = 2000;

class SupportTicketState {
  const SupportTicketState({this.busy = false, this.error});
  final bool busy;
  final String? error;

  SupportTicketState copyWith({bool? busy, Object? error = _unset}) =>
      SupportTicketState(
        busy: busy ?? this.busy,
        error: identical(error, _unset) ? this.error : error as String?,
      );
}

/// Files a support ticket from the mobile Help page (`POST /v1/support/tickets`). The reporter is
/// the authenticated caller (never sent in the body). `kind` is the toggle; `message` is the
/// free-text body (trimmed, non-empty, ≤ [kMaxSupportTicketMessageLen] — the server re-validates).
@riverpod
class SupportTicketController extends _$SupportTicketController {
  @override
  SupportTicketState build() => const SupportTicketState();

  Future<SupportTicketOutcome> submit({
    required SupportTicketKind kind,
    required String message,
  }) async {
    // Re-entrancy latch (no double submit).
    if (state.busy) {
      return SupportTicketOutcome.error;
    }
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final text = message.trim();
    // Client-side guard so an empty body never costs a round-trip (the server enforces the same).
    if (text.isEmpty) {
      state = state.copyWith(
        busy: false,
        error: isThai ? 'กรุณากรอกข้อความ' : 'Please enter a message',
      );
      return SupportTicketOutcome.error;
    }
    state = state.copyWith(busy: true, error: null);
    try {
      await ref.read(pguardApiProvider).post(
        '/support/tickets',
        data: {'kind': kind.wire, 'message': text},
      );
      state = state.copyWith(busy: false);
      return SupportTicketOutcome.sent;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: localizeApiError(isThai, e));
      return SupportTicketOutcome.error;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return SupportTicketOutcome.error;
    }
  }
}
