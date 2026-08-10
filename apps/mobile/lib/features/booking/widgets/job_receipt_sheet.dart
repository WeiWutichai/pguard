import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/org_settings_controller.dart';
import '../../../core/controllers/profile_controller.dart';
import '../../../core/controllers/receipt.dart' show ReceiptData, ReceiptKind;
import '../../../core/models/booking.dart';
import '../../../core/models/money.dart';
import '../../../core/models/org_settings.dart';
import '../../../core/models/payment.dart';
import '../../../widgets/pg_logo_mark.dart';

/// The job receipt, rendered as a FULL THAI TAX INVOICE
/// (ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี · Original Receipt / Tax Invoice) — the document a customer
/// can hand to their accountant, not a summary card. Structure follows the standard Thai e-receipt:
/// issuer (company) block → document title → number + date → buyer block → the
/// `รายการ / จำนวนเงิน / ภาษีมูลค่าเพิ่ม / รวมเงิน` item table → grand total → payment method.
///
/// WHY IT IS A TAX INVOICE NOW: catalog prices went VAT-EXCLUSIVE and 7% VAT is charged on top, so
/// the platform collects tax and must document it. All amounts print to TWO DECIMALS here — a tax
/// document is not the place to round.
///
/// RECEIPT SOURCE (a deliberate, flagged limitation):
///   • The CUSTOMER passes their settled [payment] (from owner-scoped `GET /v1/payments`) so the
///     authoritative `subtotal` / `vat_amount` / `grand_total` (and any refund / withheld
///     cancellation fee) are printed exactly as charged.
///   • The GUARD has NO readable payment: `GET /v1/payments` is owner-scoped and
///     `GET /v1/payments/{id}` is owner-or-admin only. So the guard passes `payment: null`, the
///     figures are derived from the booking, and the document is labelled an ESTIMATE rather than
///     pretending to be a tax invoice for a charge it cannot see.
///
/// BACKEND FOLLOW-UP (flagged): there is no receipt endpoint in `contracts/openapi/payment.yaml`,
/// and the issuer block's source (`GET /v1/admin/org-settings`) is ADMIN-ONLY — a customer cannot
/// read the company name/TIN/address their own tax invoice legally needs. See
/// [orgSettingsProvider]; until a customer-readable route exists the header states plainly that the
/// company details are not configured.
Future<void> showJobReceiptSheet(
  BuildContext context, {
  required Booking booking,
  required Payment? payment,
  required bool isThai,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: PgTokens.colorSurface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              PgTokens.space5, 0, PgTokens.space5, PgTokens.space5),
          child: JobReceiptBody(
            booking: booking,
            payment: payment,
            isThai: isThai,
          ),
        ),
      ),
    ),
  );
}

/// The tax-invoice body. Pulled out of the sheet so it can also be embedded inline (e.g. on the
/// customer's completion summary). Read-only; every figure is the payment service's, not the
/// client's, whenever a settled payment is available.
class JobReceiptBody extends ConsumerWidget {
  const JobReceiptBody({
    super.key,
    required this.booking,
    required this.payment,
    required this.isThai,
  });

  final Booking booking;
  final Payment? payment;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ReceiptData.from(booking: booking, payment: payment);
    // The issuer block. Best-effort: `null` while it loads, when it is not configured, or when the
    // route is unreadable for this role — all three render the same honest gap notice.
    final org = ref.watch(orgSettingsProvider).valueOrNull;
    // The buyer block. Only a CUSTOMER's own profile can name the buyer; a guard reading a
    // booking-derived copy has no customer identity to print, and we do not invent one.
    final me = ref.watch(profileControllerProvider).valueOrNull;
    final buyerName =
        (me != null && me.isCustomer) ? me.fullName?.trim() : null;
    final buyerAddress =
        (me != null && me.isCustomer) ? me.address?.trim() : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IssuerHeader(org: org, isThai: isThai),
        const SizedBox(height: PgTokens.space4),
        _DocumentTitle(isThai: isThai, kind: data.kind),
        const SizedBox(height: PgTokens.space3),
        _MetaRow(
          label: isThai ? 'เลขที่ / No.' : 'No.',
          value: data.documentNumber,
        ),
        const SizedBox(height: PgTokens.space1),
        _MetaRow(
          label: isThai ? 'วันที่ / Date' : 'Date',
          value: data.issuedAt != null
              ? ReceiptData.formatIssuedDate(data.issuedAt!, isThai: isThai)
              : '—',
        ),
        const SizedBox(height: PgTokens.space4),
        _BuyerBlock(
          isThai: isThai,
          name: buyerName,
          address: buyerAddress,
          siteAddress: booking.address,
        ),
        const SizedBox(height: PgTokens.space4),
        _ItemsTable(data: data, isThai: isThai),
        if (data.actualHours != null && data.bookedHours != null) ...[
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai
                ? 'คิดตามชั่วโมงจริง ${data.actualHours} ชม. (จองไว้ ${data.bookedHours} ชม.)'
                : 'Billed on the actual ${data.actualHours} hr worked '
                    '(${data.bookedHours} hr booked)',
            style:
                const TextStyle(fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
        ],
        if (data.hasAdjustments) ...[
          const SizedBox(height: PgTokens.space3),
          _AdjustmentsBlock(data: data, isThai: isThai),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
          child: Divider(height: 1, color: PgTokens.colorBorder),
        ),
        _MetaRow(
          label: isThai ? 'ชำระโดย / Payment method' : 'Payment method',
          value: ReceiptData.paymentMethodLabel(data.paymentMethod,
              isThai: isThai),
        ),
        if (data.isEstimate) ...[
          const SizedBox(height: PgTokens.space3),
          _Notice(
            icon: Icons.info_outline,
            text: isThai
                ? 'เอกสารนี้เป็นยอดประมาณจากการจอง ไม่ใช่ใบกำกับภาษีที่ออกจากยอดที่เรียกเก็บจริง — '
                    'ยอดที่ชำระจริงดูได้จากฝั่งลูกค้า'
                : 'These figures are estimated from the booking — this copy is not issued against '
                    "a settled charge. The amount actually paid is on the customer's side.",
          ),
        ],
      ],
    );
  }
}

/// The issuer (company) block: the pguard mark + legal name, TIN and registered address.
///
/// When the org profile is missing, this says so — a blank letterhead on a tax document reads as a
/// broken app, and worse, hides that the document is not legally valid.
class _IssuerHeader extends StatelessWidget {
  const _IssuerHeader({required this.org, required this.isThai});

  final OrgSettings? org;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final configured = org != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The brand mark is DRAWN from the design tokens (no image asset in the app).
            const PgLogoMark(size: 34),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org?.companyName ??
                        (isThai
                            ? 'ยังไม่ได้ตั้งค่าข้อมูลบริษัท'
                            : 'Company details not set up'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: configured
                          ? PgTokens.colorTextStrong
                          : PgTokens.colorTextMuted,
                    ),
                  ),
                  if (org?.taxId != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      isThai
                          ? 'เลขประจำตัวผู้เสียภาษี ${org!.taxId}'
                          : 'Tax ID ${org!.taxId}',
                      style: const TextStyle(
                          fontSize: 12, color: PgTokens.colorTextMuted),
                    ),
                  ],
                  if (org?.address != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      org!.address!,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: PgTokens.colorTextMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!configured) ...[
          const SizedBox(height: PgTokens.space3),
          _Notice(
            icon: Icons.warning_amber_outlined,
            warn: true,
            text: isThai
                ? 'ยังไม่มีชื่อบริษัท เลขประจำตัวผู้เสียภาษี และที่อยู่ในระบบ — '
                    'เอกสารนี้จึงยังไม่สมบูรณ์ตามข้อกำหนดของใบกำกับภาษี '
                    'กรุณาติดต่อผู้ดูแลระบบเพื่อขอใบกำกับภาษีฉบับเต็ม'
                : "The company name, tax ID and address aren't configured, so this document is "
                    'not a complete tax invoice. Contact support for a full copy.',
          ),
        ],
      ],
    );
  }
}

/// `ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี` + `Original Receipt / Tax Invoice` — or the honest
/// lesser title when the document cannot claim to be a tax invoice.
class _DocumentTitle extends StatelessWidget {
  const _DocumentTitle({required this.isThai, required this.kind});

  final bool isThai;

  /// A booking-derived copy is an estimate and a pre-VAT charge is a plain receipt; neither is
  /// titled as a tax invoice.
  final ReceiptKind kind;

  String get _th => switch (kind) {
        ReceiptKind.taxInvoice => 'ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี',
        ReceiptKind.receiptNoVat => 'ต้นฉบับ ใบเสร็จรับเงิน',
        ReceiptKind.estimate => 'ใบสรุปค่าบริการ (ประมาณการ)',
      };

  String get _en => switch (kind) {
        ReceiptKind.taxInvoice => 'Original Receipt / Tax Invoice',
        ReceiptKind.receiptNoVat => 'Original Receipt',
        ReceiptKind.estimate => 'Estimated statement',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: PgTokens.space3, horizontal: PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Column(
        children: [
          Text(
            _th,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: PgTokens.colorTextStrong,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _en,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.3,
                color: PgTokens.colorTextMuted),
          ),
        ],
      ),
    );
  }
}

/// The buyer block — who the document is made out to.
class _BuyerBlock extends StatelessWidget {
  const _BuyerBlock({
    required this.isThai,
    required this.name,
    required this.address,
    required this.siteAddress,
  });

  final bool isThai;
  final String? name;
  final String? address;

  /// The job site, used as the address only when the buyer has no registered one.
  final String? siteAddress;

  @override
  Widget build(BuildContext context) {
    final resolvedAddress =
        (address != null && address!.isNotEmpty) ? address : siteAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isThai ? 'ลูกค้า / Customer' : 'Customer',
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorTextMuted),
        ),
        const SizedBox(height: 3),
        Text(
          (name != null && name!.isNotEmpty) ? name! : '—',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (resolvedAddress != null && resolvedAddress.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            resolvedAddress,
            style: const TextStyle(
                fontSize: 12, height: 1.35, color: PgTokens.colorTextMuted),
          ),
        ],
      ],
    );
  }
}

/// The item table: `รายการ / จำนวนเงิน / ภาษีมูลค่าเพิ่ม / รวมเงิน` + the grand-total row.
/// Amounts are ALWAYS two decimals (money columns are right-aligned, tabular figures).
class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.data, required this.isThai});

  final ReceiptData data;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PgTokens.colorBorder),
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Column(
        children: [
          // Header row.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: PgTokens.space3, vertical: PgTokens.space2),
            decoration: const BoxDecoration(
              color: PgTokens.colorSunken,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(PgTokens.radiusLg)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    isThai ? 'รายการ' : 'Description',
                    style: _headStyle,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    isThai ? 'จำนวนเงิน' : 'Amount',
                    textAlign: TextAlign.right,
                    style: _headStyle,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    isThai ? 'ภาษีมูลค่าเพิ่ม' : 'VAT',
                    textAlign: TextAlign.right,
                    style: _headStyle,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    isThai ? 'รวมเงิน' : 'Total',
                    textAlign: TextAlign.right,
                    style: _headStyle,
                  ),
                ),
              ],
            ),
          ),
          for (final line in data.lines)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: PgTokens.space3, vertical: PgTokens.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.label(isThai),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (line.note(isThai) != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            line.note(isThai)!,
                            style: const TextStyle(
                                fontSize: 11, color: PgTokens.colorTextMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(flex: 3, child: _Amount(line.amountSatang)),
                  Expanded(flex: 3, child: _Amount(line.vatSatang)),
                  Expanded(
                      flex: 3, child: _Amount(line.totalSatang, bold: true)),
                ],
              ),
            ),
          const Divider(height: 1, color: PgTokens.colorBorder),
          // Subtotal + VAT summary, so the tax the customer paid is never folded into one number.
          Padding(
            padding: const EdgeInsets.fromLTRB(PgTokens.space3, PgTokens.space3,
                PgTokens.space3, PgTokens.space2),
            child: Column(
              children: [
                _SummaryRow(
                  label: isThai ? 'รวมเป็นเงิน' : 'Subtotal',
                  satang: data.subtotalSatang,
                ),
                const SizedBox(height: PgTokens.space2),
                _SummaryRow(
                  label: isThai
                      ? 'ภาษีมูลค่าเพิ่ม ${Money.vatPercent}%'
                      : 'VAT ${Money.vatPercent}%',
                  satang: data.vatSatang,
                ),
              ],
            ),
          ),
          // Grand total.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: PgTokens.space3, vertical: PgTokens.space3),
            decoration: const BoxDecoration(
              color: PgTokens.colorGreen50,
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(PgTokens.radiusLg)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isThai ? 'จำนวนเงินรวมทั้งสิ้น' : 'Grand Total',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: PgTokens.colorGreen900),
                  ),
                ),
                Text(
                  Money.format(data.grandTotalSatang, decimals: true),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: PgTokens.colorGreen800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: PgTokens.colorTextMuted,
  );
}

/// What happened to the money AFTER the charge: a withheld cancellation fee and/or a refund.
/// Kept OUT of the VAT table — these are adjustments to the settlement, not taxable line items.
class _AdjustmentsBlock extends StatelessWidget {
  const _AdjustmentsBlock({required this.data, required this.isThai});

  final ReceiptData data;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorAmber50,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorAmber200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.cancellationFeeSatang > 0) ...[
            _SummaryRow(
              label: isThai
                  ? 'ค่าธรรมเนียมการยกเลิก'
                  : 'Cancellation fee withheld',
              satang: data.cancellationFeeSatang,
              color: PgTokens.colorAmber700,
            ),
            const SizedBox(height: PgTokens.space2),
          ],
          if (data.refundSatang > 0) ...[
            _SummaryRow(
              label: isThai ? 'ยอดคืนเงิน' : 'Refund',
              satang: data.refundSatang,
              color: PgTokens.colorAmber700,
            ),
            const SizedBox(height: PgTokens.space2),
            _SummaryRow(
              label: isThai ? 'ยอดชำระสุทธิ' : 'Net paid',
              satang: data.netPaidSatang,
              bold: true,
            ),
            const SizedBox(height: PgTokens.space2),
          ],
          Text(
            data.cancellationFeeSatang > 0
                ? (isThai
                    ? 'ยกเลิกก่อนเริ่มงาน — หักค่าธรรมเนียมไม่เกินยอดที่ชำระไว้ ส่วนที่เหลือคืนเงินเต็มจำนวน'
                    : 'Cancelled before the job started — the fee is capped at what was paid and '
                        'the remainder is refunded in full.')
                : (isThai
                    ? 'ยอดคืนเงินจะถูกดำเนินการโดยทีมแอดมินภายหลัง'
                    : 'The refund is processed by the admin team.'),
            style:
                const TextStyle(fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
        ],
      ),
    );
  }
}

/// A right-aligned money cell — always two decimals, tabular figures so the columns line up.
class _Amount extends StatelessWidget {
  const _Amount(this.satang, {this.bold = false});

  final int satang;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      Money.format(satang, decimals: true, symbol: false),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: PgTokens.colorText,
      ),
    );
  }
}

/// A label + money row (subtotal, VAT, refund …). Two decimals, symbol shown.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.satang,
    this.bold = false,
    this.color,
  });

  final String label;
  final int satang;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? PgTokens.colorTextMuted,
            ),
          ),
        ),
        Text(
          Money.format(satang, decimals: true),
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? PgTokens.colorText,
          ),
        ),
      ],
    );
  }
}

/// A label/value line for the document metadata (number, date, payment method).
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// A small inline notice (info / warning) used for the honest gaps in the document.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.warn = false});

  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: warn ? PgTokens.colorWarningBg : PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 15,
              color: warn ? PgTokens.colorAmber700 : PgTokens.colorTextMuted),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: warn ? PgTokens.colorAmber900 : PgTokens.colorTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
