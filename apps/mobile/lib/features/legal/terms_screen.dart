import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/terms_acceptance.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// The bundled terms asset (extracted from the company's .docx — see pubspec `assets/legal/`).
const String kTermsAsset = 'assets/legal/terms_th.txt';

/// Bumped when the bundled document changes — a stored acceptance of an older version is not a
/// valid acceptance of this one (the document's own §33 reserves re-confirmation on material
/// changes).
const String kTermsVersion = '2569-08-01';

/// The bundled terms document, loaded once and cached.
///
/// The load lives in a provider rather than inline in the screen so the document is fetched once per
/// app run (a re-open renders instantly) and so widget tests can supply the text directly instead of
/// depending on real asset I/O.
final termsDocumentProvider =
    FutureProvider<String>((ref) => rootBundle.loadString(kTermsAsset));

/// Gate a registration on the terms: returns `true` only when the CURRENT terms version has been
/// accepted, opening [TermsScreen] to ask when it hasn't. Callers MUST `await` this and abort the
/// registration when it returns `false` — that is what keeps a non-accepting user from proceeding.
Future<bool> ensureTermsAccepted(BuildContext context, WidgetRef ref) async {
  if (ref.read(termsAcceptedVersionProvider) == kTermsVersion) return true;
  final accepted = await context.push<bool>('/auth/terms');
  if (accepted != true) return false;
  ref.read(termsAcceptedVersionProvider.notifier).state = kTermsVersion;
  return true;
}

/// An inline "ข้อตกลงการใช้งาน" / "นโยบายความเป็นส่วนตัว" link that opens the document READ-ONLY.
///
/// A [WidgetSpan] rather than a [TextSpan] + recognizer so there is no gesture-recognizer to dispose
/// from a stateless build.
InlineSpan termsLinkSpan(BuildContext context, String label) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: () => context.push('/auth/terms?read=1'),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: PgTokens.colorBrand,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: PgTokens.colorBrand,
          ),
        ),
      ),
    );

/// THE terms + privacy gate shown BEFORE an account (or an added role) is registered.
///
/// The customer/guard registration paths must not create anything until this screen returns `true`:
/// the user has to tick all three consents from the document's own "แบบยืนยันการยอมรับข้อกำหนด"
/// (accept the terms · acknowledge the privacy policy · EXPLICIT consent for sensitive data — face
/// + criminal-record checks, which PDPA requires separately). Until then the primary action stays
/// disabled and there is no way forward from here; backing out simply returns "not accepted" and
/// nothing is registered.
///
/// Opened two ways:
///  - as a GATE (`readOnly: false`, the default) — pops `true` on accept, `false`/null otherwise;
///  - as a READ-ONLY document (`readOnly: true`) from the "ข้อตกลงการใช้งาน / นโยบายความเป็นส่วนตัว"
///    links, where there is nothing to accept.
///
/// The Thai document is the binding text, so it is rendered verbatim in Thai for both locales; only
/// the surrounding chrome follows the app language.
class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _sensitive = false;

  bool get _allAccepted => _terms && _privacy && _sensitive;

  /// Consent is only meaningful once the text being consented to is actually on screen.
  bool get _documentReady =>
      (ref.watch(termsDocumentProvider).valueOrNull ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'ข้อกำหนดการใช้บริการ' : 'Terms of Service',
        subtitle: isThai
            ? 'โปรดอ่านและยอมรับก่อนสมัครสมาชิก'
            : 'Please read and accept before registering',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ref.watch(termsDocumentProvider).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => _LoadFailed(isThai: isThai),
                    // An empty asset is a packaging failure, not a document — never present it as
                    // "the terms" with a live accept button under it.
                    data: (text) => text.trim().isEmpty
                        ? _LoadFailed(isThai: isThai)
                        : _DocumentBody(text: text),
                  ),
            ),
            if (!widget.readOnly && _documentReady)
              _AcceptancePanel(
                isThai: isThai,
                terms: _terms,
                privacy: _privacy,
                sensitive: _sensitive,
                onTerms: (v) => setState(() => _terms = v),
                onPrivacy: (v) => setState(() => _privacy = v),
                onSensitive: (v) => setState(() => _sensitive = v),
                canContinue: _allAccepted,
                // Accepting is the ONLY way forward; declining is simply not accepting (the button
                // stays disabled and the user remains on this screen).
                onAccept: () => context.pop(true),
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space5),
          child: Text(
            isThai
                ? 'โหลดเอกสารไม่สำเร็จ กรุณาลองใหม่'
                : 'Could not load the document — please try again',
            textAlign: TextAlign.center,
            style: const TextStyle(color: PgTokens.colorDanger),
          ),
        ),
      );
}

/// The document itself: numbered clauses render as headings, everything else as body copy.
class _DocumentBody extends StatelessWidget {
  const _DocumentBody({required this.text});

  final String text;

  static final RegExp _heading = RegExp(r'^\d+\.\s');

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space5, PgTokens.space4, PgTokens.space5, PgTokens.space4),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final isHeading = _heading.hasMatch(line);
        // The very first line is the document title.
        final isTitle = i == 0;
        return Padding(
          padding: EdgeInsets.only(top: isHeading ? PgTokens.space4 : 6),
          child: Text(
            line,
            style: TextStyle(
              fontSize: isTitle ? 17 : (isHeading ? 15 : 13.5),
              height: 1.6,
              fontWeight:
                  isTitle || isHeading ? FontWeight.w700 : FontWeight.w400,
              color: isTitle || isHeading
                  ? PgTokens.colorText
                  : PgTokens.colorTextMuted,
            ),
          ),
        );
      },
    );
  }
}

/// The three consents from the document's acceptance form + the single way forward.
class _AcceptancePanel extends StatelessWidget {
  const _AcceptancePanel({
    required this.isThai,
    required this.terms,
    required this.privacy,
    required this.sensitive,
    required this.onTerms,
    required this.onPrivacy,
    required this.onSensitive,
    required this.canContinue,
    required this.onAccept,
  });

  final bool isThai;
  final bool terms;
  final bool privacy;
  final bool sensitive;
  final ValueChanged<bool> onTerms;
  final ValueChanged<bool> onPrivacy;
  final ValueChanged<bool> onSensitive;
  final bool canContinue;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space4, PgTokens.space2, PgTokens.space4, PgTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Verbatim from the document (Thai is the binding text).
          _ConsentTile(
            value: terms,
            onChanged: onTerms,
            label:
                'ข้าพเจ้ายืนยันว่าได้อ่านและยอมรับข้อกำหนดและเงื่อนไขการใช้บริการ PGUARD',
          ),
          _ConsentTile(
            value: privacy,
            onChanged: onPrivacy,
            label:
                'ข้าพเจ้ารับทราบนโยบายคุ้มครองข้อมูลส่วนบุคคลของ PGUARD และเข้าใจว่าบริษัทจะเก็บรวบรวม ใช้ และเปิดเผยข้อมูลตามวัตถุประสงค์ที่ระบุไว้',
          ),
          _ConsentTile(
            value: sensitive,
            onChanged: onSensitive,
            label:
                'ข้าพเจ้ายินยอมโดยชัดแจ้งให้ PGUARD เก็บรวบรวม ใช้ และเปิดเผยข้อมูลอ่อนไหวที่จำเป็น เช่น ข้อมูลใบหน้าเพื่อยืนยันตัวตน และข้อมูลประวัติอาชญากรรม เพื่อการตรวจสอบคุณสมบัติ การรักษาความปลอดภัย และการให้บริการตามที่แจ้งไว้',
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            canContinue
                ? (isThai
                    ? 'ขอบคุณ — กดดำเนินการต่อเพื่อสมัครสมาชิก'
                    : 'Thank you — continue to register')
                : (isThai
                    ? 'ต้องยอมรับครบทุกข้อจึงจะสมัครสมาชิกต่อได้'
                    : 'All three consents are required to continue'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color:
                  canContinue ? PgTokens.colorTextMuted : PgTokens.colorWarning,
            ),
          ),
          const SizedBox(height: PgTokens.space2),
          PgPrimaryButton(
            label: isThai ? 'ยอมรับและดำเนินการต่อ' : 'Accept and continue',
            onPressed: canContinue ? onAccept : null,
          ),
        ],
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: PgTokens.space2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12.5, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
