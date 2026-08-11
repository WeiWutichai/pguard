// The DOWNLOADABLE tax invoice: a [ReceiptData] rendered to real PDF bytes.
//
// ONE SOURCE OF TRUTH FOR THE MONEY. Every figure printed here is read off [ReceiptData] — the same
// pure derivation the on-screen sheet lays out (`features/booking/widgets/job_receipt_sheet.dart`).
// This file performs NO arithmetic of its own beyond formatting satang for display. A PDF that
// recomputed anything could disagree with the sheet the customer just looked at, and a tax document
// that contradicts itself is worse than no download at all.
//
// The document's WORDS come from [ReceiptCopy] for the same reason: the title has to refuse to say
// "ใบกำกับภาษี" on an estimate in both renderings, not just one.
//
// THAI MUST RENDER. The pdf package's built-in Type-1 faces (Helvetica et al.) carry no Thai
// glyphs — a document built with them prints every Thai word as a blank box, which would be a
// worse outcome than the missing download it replaces. The app's own bundled IBM Plex Sans Thai
// faces are embedded instead (see [ReceiptPdfFonts]), so the PDF reads exactly like the sheet.
// `test/unit/receipt_pdf_test.dart` asserts the face is really in the bytes.
//
// TESTABLE WITHOUT WIDGETS: the only Flutter surface is `AssetBundle` (to read the bundled TTFs),
// so the whole document can be built — and its text asserted — in a plain test.

import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../controllers/receipt.dart';
import '../models/money.dart';
import '../models/org_settings.dart';

/// The three IBM Plex Sans Thai faces the invoice uses, parsed once.
///
/// Parsing a TTF is the expensive part of building the document, so a caller that produces several
/// receipts can [load] once and pass the result to every [buildReceiptPdf].
class ReceiptPdfFonts {
  const ReceiptPdfFonts({
    required this.regular,
    required this.semiBold,
    required this.bold,
  });

  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;

  /// The bundled faces (declared in `pubspec.yaml` under family `IBMPlexSansThai`). Thai text is
  /// the whole point: these carry U+0E01–U+0E5B and the ฿ sign (U+0E3F).
  static const String regularAsset = 'assets/fonts/IBMPlexSansThai-Regular.ttf';
  static const String semiBoldAsset =
      'assets/fonts/IBMPlexSansThai-SemiBold.ttf';
  static const String boldAsset = 'assets/fonts/IBMPlexSansThai-Bold.ttf';

  /// Read + parse the faces from [bundle] (the app's `rootBundle` by default).
  static Future<ReceiptPdfFonts> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final regular = pw.Font.ttf(await b.load(regularAsset));
    final semiBold = pw.Font.ttf(await b.load(semiBoldAsset));
    final bold = pw.Font.ttf(await b.load(boldAsset));
    return ReceiptPdfFonts(
      regular: regular,
      semiBold: semiBold,
      bold: bold,
    );
  }
}

/// Everything the printed document needs that is NOT money: who issued it, who it is made out to,
/// and which language to read it in. The money is [data] and only [data].
class ReceiptPdfDocument {
  const ReceiptPdfDocument({
    required this.data,
    required this.isThai,
    this.org,
    this.buyerName,
    this.buyerAddress,
    this.siteAddress,
  });

  /// The derived document — lines, VAT allocation, totals, number, date, method.
  final ReceiptData data;

  final bool isThai;

  /// The issuer (company) block. `null` when it is unset or unreadable for this role, which the
  /// header STATES rather than printing a blank letterhead ([ReceiptCopy.companyIncompleteNotice]).
  final OrgSettings? org;

  /// The buyer. Only a customer reading their own receipt can name the buyer; a guard's
  /// booking-derived copy leaves it blank rather than inventing one.
  final String? buyerName;
  final String? buyerAddress;

  /// The job site — used as the buyer address only when the buyer has no registered one.
  final String? siteAddress;

  /// The file the customer ends up with in their Downloads / LINE / mail. Named after the document
  /// number so it is identifiable months later next to a hundred other PDFs — never a temp name.
  String get fileName => 'pguard-${_safeSegment(data.documentNumber)}.pdf';

  /// The share sheet's subject line (used as the mail subject on iOS/Android).
  String get shareSubject =>
      '${ReceiptCopy.titleTh(data.kind)} ${data.documentNumber}';

  /// Keep the filename to characters every OS, mail client and messenger accepts.
  static String _safeSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    return cleaned.isEmpty ? 'receipt' : cleaned;
  }
}

/// Build the tax invoice and return the PDF bytes.
///
/// [fonts] is optional purely as a performance seam — omitted, the bundled faces are loaded on
/// demand. It is never a way to render the document WITHOUT Thai support.
Future<Uint8List> buildReceiptPdf(
  ReceiptPdfDocument doc, {
  ReceiptPdfFonts? fonts,
  AssetBundle? bundle,
}) async {
  final f = fonts ?? await ReceiptPdfFonts.load(bundle: bundle);
  final pdf = pw.Document(
    title: '${ReceiptCopy.titleEn(doc.data.kind)} ${doc.data.documentNumber}',
    author: doc.org?.companyName,
    creator: 'pguard',
    subject: ReceiptCopy.titleTh(doc.data.kind),
    // Every face is a Thai face — there is no Latin-only fallback that could silently swallow a
    // Thai string and print boxes.
    theme: pw.ThemeData.withFont(
      base: f.regular,
      bold: f.bold,
      fontFallback: [f.regular],
    ),
  );

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => _body(doc, f),
    ),
  );

  return pdf.save();
}

// ---------------------------------------------------------------------------------------------
// Layout — mirrors the on-screen sheet section for section.
// ---------------------------------------------------------------------------------------------

List<pw.Widget> _body(ReceiptPdfDocument doc, ReceiptPdfFonts f) {
  final data = doc.data;
  final isThai = doc.isThai;
  return [
    _issuerHeader(doc, f),
    pw.SizedBox(height: 16),
    _documentTitle(data.kind, f),
    pw.SizedBox(height: 12),
    _metaRow(ReceiptCopy.number(isThai), data.documentNumber, f),
    pw.SizedBox(height: 4),
    _metaRow(
      ReceiptCopy.date(isThai),
      data.issuedAt != null
          ? ReceiptData.formatIssuedDate(data.issuedAt!, isThai: isThai)
          : '—',
      f,
    ),
    pw.SizedBox(height: 16),
    _buyerBlock(doc, f),
    pw.SizedBox(height: 16),
    _itemsTable(doc, f),
    if (data.actualHours != null && data.bookedHours != null) ...[
      pw.SizedBox(height: 8),
      pw.Text(
        ReceiptCopy.reconciledHours(
          isThai,
          actualHours: data.actualHours!,
          bookedHours: data.bookedHours!,
        ),
        style: pw.TextStyle(font: f.regular, fontSize: 8.5, color: _muted),
      ),
    ],
    if (data.hasAdjustments) ...[
      pw.SizedBox(height: 12),
      _adjustmentsBlock(doc, f),
    ],
    pw.SizedBox(height: 12),
    pw.Divider(height: 1, thickness: 0.7, color: _border),
    pw.SizedBox(height: 12),
    _metaRow(
      ReceiptCopy.paymentMethod(isThai),
      ReceiptData.paymentMethodLabel(data.paymentMethod, isThai: isThai),
      f,
    ),
    if (data.isEstimate) ...[
      pw.SizedBox(height: 12),
      _notice(ReceiptCopy.estimateNotice(isThai), f),
    ],
  ];
}

/// The issuer block: the pguard mark + legal name, TIN and registered address — or, when the org
/// profile is unset, the named gap plus the warning that the document is therefore incomplete.
pw.Widget _issuerHeader(ReceiptPdfDocument doc, ReceiptPdfFonts f) {
  final org = doc.org;
  final isThai = doc.isThai;
  final configured = org != null;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 34, height: 36, child: _logoMark()),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  org?.companyName ?? ReceiptCopy.companyUnset(isThai),
                  style: pw.TextStyle(
                    font: f.bold,
                    fontSize: 13,
                    color: configured ? _textStrong : _muted,
                  ),
                ),
                if (org?.taxId != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    ReceiptCopy.taxIdLine(isThai, org!.taxId!),
                    style: pw.TextStyle(
                        font: f.regular, fontSize: 9, color: _muted),
                  ),
                ],
                if (org?.address != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    org!.address!,
                    style: pw.TextStyle(
                      font: f.regular,
                      fontSize: 9,
                      lineSpacing: 1.5,
                      color: _muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      if (!configured) ...[
        pw.SizedBox(height: 12),
        _notice(ReceiptCopy.companyIncompleteNotice(isThai), f, warn: true),
      ],
    ],
  );
}

/// The pguard mark, from the SAME paths the app draws (`widgets/pg_logo_mark.dart`, hi-fi SVG
/// viewBox 0 0 100 106) — one piece of artwork across screen and paper.
pw.Widget _logoMark() => pw.SvgImage(
      svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 106">'
          '<defs><linearGradient id="pgMark" x1="0" y1="0" x2="0" y2="1">'
          '<stop offset="0" stop-color="${_hex(PgTokens.colorPrimary)}"/>'
          '<stop offset="1" stop-color="${_hex(PgTokens.colorBrand)}"/>'
          '</linearGradient></defs>'
          '<path d="M50 4 L88 18 V50 C88 78 72 95 50 104 C28 95 12 78 12 50 V18 Z" '
          'fill="url(#pgMark)"/>'
          '<path d="M50 30 C41 30 34 37 34 46 C34 58 50 74 50 74 C50 74 66 58 66 46 '
          'C66 37 59 30 50 30 Z" fill="${_hex(PgTokens.colorSurface)}"/>'
          '<circle cx="50" cy="46" r="7.5" fill="${_hex(PgTokens.colorPrimary)}"/>'
          '</svg>',
    );

/// `ต้นฉบับ ใบเสร็จรับเงิน / ใบกำกับภาษี` + the English sub-line — or the honest lesser title.
pw.Widget _documentTitle(ReceiptKind kind, ReceiptPdfFonts f) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: _sunken,
        borderRadius: pw.BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            ReceiptCopy.titleTh(kind),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: f.bold, fontSize: 13, color: _textStrong),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            ReceiptCopy.titleEn(kind),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: f.regular, fontSize: 9, color: _muted),
          ),
        ],
      ),
    );

/// Who the document is made out to.
pw.Widget _buyerBlock(ReceiptPdfDocument doc, ReceiptPdfFonts f) {
  final address = (doc.buyerAddress != null && doc.buyerAddress!.isNotEmpty)
      ? doc.buyerAddress
      : doc.siteAddress;
  final name = (doc.buyerName != null && doc.buyerName!.isNotEmpty)
      ? doc.buyerName!
      : '—';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        ReceiptCopy.customer(doc.isThai),
        style: pw.TextStyle(font: f.semiBold, fontSize: 8.5, color: _muted),
      ),
      pw.SizedBox(height: 3),
      pw.Text(name, style: pw.TextStyle(font: f.semiBold, fontSize: 11)),
      if (address != null && address.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          address,
          style: pw.TextStyle(
              font: f.regular, fontSize: 9, lineSpacing: 1.5, color: _muted),
        ),
      ],
    ],
  );
}

/// `รายการ / จำนวนเงิน / ภาษีมูลค่าเพิ่ม / รวมเงิน`, the subtotal + VAT summary, then the grand
/// total — the same four columns and the same 5/3/3/3 proportions as the sheet.
pw.Widget _itemsTable(ReceiptPdfDocument doc, ReceiptPdfFonts f) {
  final data = doc.data;
  final isThai = doc.isThai;
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _border, width: 0.7),
      borderRadius: pw.BorderRadius.circular(PgTokens.radiusLg),
    ),
    child: pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _sunken,
            borderRadius: const pw.BorderRadius.only(
              topLeft: pw.Radius.circular(PgTokens.radiusLg),
              topRight: pw.Radius.circular(PgTokens.radiusLg),
            ),
          ),
          child: pw.Row(
            children: [
              _headCell(ReceiptCopy.colDescription(isThai), f, flex: 5),
              _headCell(ReceiptCopy.colAmount(isThai), f,
                  flex: 3, alignRight: true),
              _headCell(ReceiptCopy.colVat(isThai), f,
                  flex: 3, alignRight: true),
              _headCell(ReceiptCopy.colTotal(isThai), f,
                  flex: 3, alignRight: true),
            ],
          ),
        ),
        for (final line in data.lines)
          pw.Padding(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        line.label(isThai),
                        style: pw.TextStyle(font: f.semiBold, fontSize: 10),
                      ),
                      if (line.note(isThai) != null) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          line.note(isThai)!,
                          style: pw.TextStyle(
                              font: f.regular, fontSize: 8.5, color: _muted),
                        ),
                      ],
                    ],
                  ),
                ),
                _amountCell(line.amountSatang, f),
                _amountCell(line.vatSatang, f),
                _amountCell(line.totalSatang, f, bold: true),
              ],
            ),
          ),
        pw.Divider(height: 1, thickness: 0.7, color: _border),
        // Subtotal + VAT, so the tax the customer paid is never folded into one number.
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: pw.Column(
            children: [
              _summaryRow(ReceiptCopy.subtotal(isThai), data.subtotalSatang, f),
              pw.SizedBox(height: 6),
              _summaryRow(
                ReceiptCopy.vat(isThai, Money.vatPercent),
                data.vatSatang,
                f,
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _green50,
            borderRadius: const pw.BorderRadius.only(
              bottomLeft: pw.Radius.circular(PgTokens.radiusLg),
              bottomRight: pw.Radius.circular(PgTokens.radiusLg),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  ReceiptCopy.grandTotal(isThai),
                  style: pw.TextStyle(
                      font: f.bold, fontSize: 11, color: _green900),
                ),
              ),
              pw.Text(
                Money.format(data.grandTotalSatang, decimals: true),
                style:
                    pw.TextStyle(font: f.bold, fontSize: 15, color: _green800),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// What happened to the money AFTER the charge — a withheld cancellation fee and/or a refund.
/// Kept OUT of the VAT table: these adjust the settlement, they are not taxable line items.
pw.Widget _adjustmentsBlock(ReceiptPdfDocument doc, ReceiptPdfFonts f) {
  final data = doc.data;
  final isThai = doc.isThai;
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: _amber50,
      border: pw.Border.all(color: _amber200, width: 0.7),
      borderRadius: pw.BorderRadius.circular(PgTokens.radiusLg),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (data.cancellationFeeSatang > 0) ...[
          _summaryRow(
            ReceiptCopy.cancellationFee(isThai),
            data.cancellationFeeSatang,
            f,
            color: _amber700,
          ),
          pw.SizedBox(height: 6),
        ],
        if (data.refundSatang > 0) ...[
          _summaryRow(ReceiptCopy.refund(isThai), data.refundSatang, f,
              color: _amber700),
          pw.SizedBox(height: 6),
          _summaryRow(ReceiptCopy.netPaid(isThai), data.netPaidSatang, f,
              bold: true),
          pw.SizedBox(height: 6),
        ],
        pw.Text(
          ReceiptCopy.adjustmentNote(isThai,
              hasCancellationFee: data.cancellationFeeSatang > 0),
          style: pw.TextStyle(font: f.regular, fontSize: 8.5, color: _muted),
        ),
      ],
    ),
  );
}

pw.Widget _headCell(String label, ReceiptPdfFonts f,
        {required int flex, bool alignRight = false}) =>
    pw.Expanded(
      flex: flex,
      child: pw.Text(
        label,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(font: f.bold, fontSize: 8.5, color: _muted),
      ),
    );

/// A right-aligned money cell — always two decimals; a tax document does not round.
pw.Widget _amountCell(int satang, ReceiptPdfFonts f, {bool bold = false}) =>
    pw.Expanded(
      flex: 3,
      child: pw.Text(
        Money.format(satang, decimals: true, symbol: false),
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          font: bold ? f.bold : f.semiBold,
          fontSize: 9.5,
          color: _text,
        ),
      ),
    );

/// A label + money row (subtotal, VAT, refund …).
pw.Widget _summaryRow(
  String label,
  int satang,
  ReceiptPdfFonts f, {
  bool bold = false,
  PdfColor? color,
}) =>
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: bold ? f.bold : f.regular,
              fontSize: 9.5,
              color: color ?? _muted,
            ),
          ),
        ),
        pw.Text(
          Money.format(satang, decimals: true),
          style: pw.TextStyle(
            font: bold ? f.bold : f.semiBold,
            fontSize: 10,
            color: color ?? _text,
          ),
        ),
      ],
    );

/// A label/value line for the document metadata (number, date, payment method).
pw.Widget _metaRow(String label, String value, ReceiptPdfFonts f) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(font: f.regular, fontSize: 9.5, color: _muted)),
        pw.Expanded(
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: f.semiBold, fontSize: 10),
          ),
        ),
      ],
    );

/// A boxed notice for the document's honest gaps (missing company block, estimate).
pw.Widget _notice(String text, ReceiptPdfFonts f, {bool warn = false}) =>
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: warn ? _warningBg : _sunken,
        borderRadius: pw.BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: f.regular,
          fontSize: 8.5,
          lineSpacing: 2,
          color: warn ? _amber900 : _muted,
        ),
      ),
    );

// ---------------------------------------------------------------------------------------------
// Design tokens → PDF colors. No hardcoded colors (CLAUDE.md): the paper uses the same palette as
// the screen, in the LIGHT scale — a printed page has no dark mode.
// ---------------------------------------------------------------------------------------------

PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());
String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

final PdfColor _text = _pdf(PgTokens.colorText);
final PdfColor _textStrong = _pdf(PgTokens.colorTextStrong);
final PdfColor _muted = _pdf(PgTokens.colorTextMuted);
final PdfColor _border = _pdf(PgTokens.colorBorder);
final PdfColor _sunken = _pdf(PgTokens.colorSunken);
final PdfColor _green50 = _pdf(PgTokens.colorGreen50);
final PdfColor _green800 = _pdf(PgTokens.colorGreen800);
final PdfColor _green900 = _pdf(PgTokens.colorGreen900);
final PdfColor _amber50 = _pdf(PgTokens.colorAmber50);
final PdfColor _amber200 = _pdf(PgTokens.colorAmber200);
final PdfColor _amber700 = _pdf(PgTokens.colorAmber700);
final PdfColor _amber900 = _pdf(PgTokens.colorAmber900);
final PdfColor _warningBg = _pdf(PgTokens.colorWarningBg);
