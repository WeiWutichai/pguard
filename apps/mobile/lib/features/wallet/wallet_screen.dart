import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/wallet_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/payment.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';

/// Customer "กระเป๋า" tab — the caller's payments from `GET /v1/payments` via
/// [WalletController]. UI per Customer_App.md Screen 13 "Receipts List" (the design's wallet
/// tab lands on the receipts list): bordered receipt cards with a mono reference, date and
/// mono amount — plus a "รวมจ่ายแล้ว / Total spent" hero (house figure derived from the
/// payments list; the spent math is pure in [WalletController]). Pull-to-refresh, no polling.
///
/// Design deltas (data the v2 contract doesn't carry — never invented):
///  - the mock's receipt rows show the GUARD NAME; a payment carries only ids, so the row
///    shows the date + a status badge instead;
///  - rows are not tappable: there is no receipt-detail endpoint (mock Screen 14's
///    fee/discount/PDF breakdown does not exist in v2).
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(walletControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'ใบเสร็จ' : 'Receipts',
        subtitle: isThai ? 'รายการชำระเงิน' : 'Your payments',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดใบเสร็จไม่สำเร็จ' : 'Could not load receipts',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.read(walletControllerProvider.notifier).refresh(),
          ),
          data: (payments) => RefreshIndicator(
            onRefresh: () =>
                ref.read(walletControllerProvider.notifier).refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _TotalSpentHero(
                    totalSatang: WalletController.totalSpentSatang(payments),
                    isThai: isThai),
                if (payments.isEmpty)
                  _EmptyWallet(isThai: isThai)
                else
                  for (final p in payments)
                    _ReceiptRow(payment: p, isThai: isThai),
                const SizedBox(height: PgTokens.space4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "รวมจ่ายแล้ว / Total spent" hero — same shape as the earnings hero (muted label + 34px
/// mono figure). Refunded charges count 0; prorated charges count their final amount.
class _TotalSpentHero extends StatelessWidget {
  const _TotalSpentHero({required this.totalSatang, required this.isThai});

  final int totalSatang;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isThai ? 'รวมจ่ายแล้ว' : 'Total spent',
            style:
                const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space1),
          Text(
            // Satang precision: ฿1/hr services prorate to sub-฿1 finals — whole-baht floors them
            // to ฿0 (the "receipts all show ฿0" bug). Matches the charge/receipt screens.
            Money.format(totalSatang, decimals: true),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()],
              color: PgTokens.colorTextStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// One receipt card per the design `.rcpt-row`: sunken receipt icon, mono reference, muted
/// date line, status badge + right-aligned mono amount.
class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.payment, required this.isThai});

  final Payment payment;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final when = payment.createdAt ?? payment.paidAt;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          PgTokens.space5, 0, PgTokens.space5, PgTokens.space3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: PgTokens.colorSunken,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 17, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  WalletController.paymentRef(payment),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'IBMPlexMono',
                    color: PgTokens.colorTextStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  when != null ? thaiShortDateYear(when, isThai: isThai) : '—',
                  style: const TextStyle(
                      fontSize: 11.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: PgTokens.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // Effective charge (final_amount wins) — keeps rows coherent with the
                // hero total; refunded rows keep the original figure (badge explains).
                // Satang precision so a sub-฿1 prorated charge isn't floored to ฿0.
                Money.format(WalletController.rowAmountSatang(payment),
                    decimals: true),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: PgTokens.colorTextStrong,
                ),
              ),
              const SizedBox(height: 3),
              _PaymentBadge(status: payment.status, isThai: isThai),
            ],
          ),
        ],
      ),
    );
  }
}

/// 10px w600 status pill: pending → amber, completed → green, refunded → info blue.
class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status, required this.isThai});

  final PaymentStatus status;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      PaymentStatus.pending => (
          PgTokens.colorWarningBg,
          PgTokens.colorAmber600
        ),
      PaymentStatus.completed => (
          PgTokens.colorGreen100,
          PgTokens.colorGreen700
        ),
      PaymentStatus.refunded => (PgTokens.colorInfoBg, PgTokens.colorInfo),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Text(
        WalletController.statusLabel(status, isThai: isThai),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// No payments yet (the spec has no designed empty state — house empty pattern).
class _EmptyWallet extends StatelessWidget {
  const _EmptyWallet({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.receipt_long_outlined,
            size: 48, color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Text(
          isThai ? 'ยังไม่มีใบเสร็จ' : 'No receipts yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        const SizedBox(height: PgTokens.space2),
        Text(
          isThai
              ? 'ใบเสร็จจะแสดงหลังชำระเงิน'
              : 'Receipts appear after you pay',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}
