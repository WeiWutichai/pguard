import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/registration_controller.dart';
import '../../../core/media/document_picker.dart';
import '../../../core/models/registration.dart';
import '../../../core/providers.dart';
import '../../../widgets/pguard_header.dart';
import '../../../widgets/primary_button.dart';
import 'guard_doc_row.dart';

/// Guard profile form — 4 design steps under a segmented top progress bar (hi-fi `.reg-prog`):
/// personal → documents (REAL `image_picker`) → payout account → review & submit, with the CTA in
/// a fixed footer shell. Submits the JSON fields the v2 contract accepts
/// (`UpsertGuardProfileRequest`: gender/dob/experience/workplace/bank) to `POST /profile/guard`
/// with the single-use `profile_token`. The bank account number is digits-only; it's sent in FULL
/// to the backend but the controller masks it before persisting any local summary (PDPA).
///
/// Document images (the 5 kinds + the passbook photo) are captured with the real picker (an
/// onboarding requirement) and validated client-side, but NOT uploaded: v2 `profile.yaml` has no
/// document-upload endpoint yet, so the step is non-blocking and the captured paths are held for
/// the future endpoint (PR-flagged).
class GuardRegistrationScreen extends ConsumerStatefulWidget {
  const GuardRegistrationScreen({super.key});

  @override
  ConsumerState<GuardRegistrationScreen> createState() =>
      _GuardRegistrationScreenState();
}

/// Display helper: age in years from an ISO `yyyy-MM-dd` date of birth (null if unparseable).
int? _ageFromIso(String? iso) {
  if (iso == null) return null;
  final dob = DateTime.tryParse(iso);
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return age < 0 ? null : age;
}

class _GuardRegistrationScreenState
    extends ConsumerState<GuardRegistrationScreen> {
  static const int _minAccountDigits = 10;
  static const int _maxAccountDigits = 15;
  static const int _totalSteps = 4;

  /// Design `.reg-step` + per-step title/subtitle (Registration.md screens 1–4).
  static const List<({String title, String subtitle})> _stepHeads = [
    (
      title: 'ข้อมูลส่วนตัว / Personal info',
      subtitle: 'กรอกตามบัตรประชาชน / As shown on your ID card',
    ),
    (
      title: 'อัปโหลดเอกสาร / Upload documents',
      subtitle: 'ถ่ายรูปหรือเลือกจากแกลเลอรี · ลายน้ำเพื่อความปลอดภัย / '
          'Camera or gallery · watermarked for safety',
    ),
    (
      title: 'บัญชีรับเงิน / Payout account',
      subtitle:
          'เงินรายได้จะโอนเข้าบัญชีนี้ / Earnings are paid to this account',
    ),
    (
      title: 'ตรวจทานข้อมูล / Review your details',
      subtitle:
          'ตรวจสอบก่อนส่งให้แอดมินอนุมัติ / Check before submitting for approval',
    ),
  ];

  /// The 4 Thai banks offered by the design's payout select (sent as the `bank_name` string the
  /// contract already accepts).
  static const List<({String value, String label})> _banks = [
    (value: 'ธนาคารกสิกรไทย', label: 'ธนาคารกสิกรไทย / Kasikornbank'),
    (
      value: 'ธนาคารไทยพาณิชย์',
      label: 'ธนาคารไทยพาณิชย์ / Siam Commercial Bank'
    ),
    (value: 'ธนาคารกรุงเทพ', label: 'ธนาคารกรุงเทพ / Bangkok Bank'),
    (value: 'ธนาคารกรุงไทย', label: 'ธนาคารกรุงไทย / Krung Thai Bank'),
  ];

  int _step = 0;

  // Personal
  String? _gender;
  String? _dob; // ISO yyyy-MM-dd
  final _experience = TextEditingController();
  final _workplace = TextEditingController();

  // Documents (real picker) — kind → file path.
  final Map<GuardDocKind, String> _docs = {};

  // Bank
  String? _bank;
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  String? _accountError;

  /// Passbook photo — held alongside [_docs] for the future upload endpoint (no contract yet).
  String? _passbookPath;

  @override
  void dispose() {
    _experience.dispose();
    _workplace.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    super.dispose();
  }

  String? _validExperience() {
    final t = _experience.text.trim();
    if (t.isEmpty) return null; // optional
    final n = int.tryParse(t);
    if (n == null || n < 0 || n > 80) {
      return 'ปีประสบการณ์ไม่ถูกต้อง (0–80) / Invalid experience (0–80)';
    }
    return null;
  }

  bool _bankIsValid() {
    final digits = _accountNumber.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < _minAccountDigits ||
        digits.length > _maxAccountDigits) {
      setState(() => _accountError =
          'เลขบัญชี $_minAccountDigits–$_maxAccountDigits หลัก / Account must be $_minAccountDigits–$_maxAccountDigits digits');
      return false;
    }
    setState(() => _accountError = null);
    return true;
  }

  /// Camera-or-gallery sheet → real picker. Shared by the 5 doc rows and the passbook box.
  Future<String?> _pickImage() async {
    final source = await showModalBottomSheet<DocSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูป / Take photo'),
              onTap: () => Navigator.pop(ctx, DocSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากคลัง / Choose from gallery'),
              onTap: () => Navigator.pop(ctx, DocSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return ref.read(documentPickerProvider).pick(source);
  }

  Future<void> _pickDoc(GuardDocKind kind) async {
    final path = await _pickImage();
    if (path != null && mounted) {
      setState(() => _docs[kind] = path);
    }
  }

  Future<void> _pickPassbook() async {
    final path = await _pickImage();
    if (path != null && mounted) {
      setState(() => _passbookPath = path);
    }
  }

  Future<void> _onContinue() async {
    if (_step == 0) {
      final err = _validExperience();
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err)));
        return;
      }
      setState(() => _step = 1);
    } else if (_step == 1) {
      setState(() => _step = 2);
    } else if (_step == 2) {
      if (!_bankIsValid()) return;
      setState(() => _step = 3);
    } else {
      await _submit();
    }
  }

  /// Header back: steps back through the flow first, then pops the route (design mockups show a
  /// single back affordance in the top bar). No-op while a submit is in flight.
  void _onBack() {
    if (ref.read(registrationControllerProvider).busy) return;
    if (_step > 0) {
      setState(() => _step -= 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _submit() async {
    // Re-validate both gated steps here too — defence in depth against any path that reaches the
    // review step with stale values (catch it client-side, not via a 400).
    final expErr = _validExperience();
    if (expErr != null) {
      setState(() => _step = 0);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(expErr)));
      return;
    }
    if (!_bankIsValid()) {
      setState(() => _step = 2);
      return;
    }
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final ok = await ctrl.submitGuardProfile(
      gender: _gender,
      dateOfBirth: _dob,
      yearsOfExperience: int.tryParse(_experience.text.trim()),
      previousWorkplace: _workplace.text,
      bankName: _bank,
      accountNumber: _accountNumber.text,
      accountName: _accountName.text,
      docPaths: Map.of(_docs),
    );
    if (ok && mounted) context.push('/auth/pending');
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'วันเกิด / Date of birth',
    );
    if (picked != null) {
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      setState(() => _dob = '${picked.year}-$m-$d');
    }
  }

  String get _ctaLabel => switch (_step) {
        1 => 'ถัดไป (${_docs.length}/5) / Next (${_docs.length}/5)',
        3 => 'ส่งใบสมัคร / Submit application',
        _ => 'ถัดไป / Next',
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationControllerProvider);
    final head = _stepHeads[_step];

    return Scaffold(
      appBar: PGuardHeader(
        title: 'ข้อมูลเจ้าหน้าที่',
        subtitle: 'Guard profile',
        showBack: true,
        onBack: _onBack,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _progressBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    PgTokens.space6, 0, PgTokens.space6, PgTokens.space6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ขั้นที่ ${_step + 1} จาก $_totalSteps',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorPrimary,
                      ),
                    ),
                    const SizedBox(height: PgTokens.space1),
                    Text(
                      head.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorText,
                      ),
                    ),
                    const SizedBox(height: PgTokens.space1),
                    Text(
                      head.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PgTokens.colorTextMuted,
                      ),
                    ),
                    const SizedBox(height: PgTokens.space6),
                    switch (_step) {
                      0 => _personalStep(),
                      1 => _documentsStep(),
                      2 => _bankStep(),
                      _ => _reviewStep(),
                    },
                  ],
                ),
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: PgTokens.space6, vertical: PgTokens.space2),
                child: Text(state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger)),
              ),
            _footer(state),
          ],
        ),
      ),
    );
  }

  /// Design `.reg-prog`: 4 flex segments, 5px tall, 3px radius, 6px gap; filled = brand-int,
  /// empty = bg-sunken; padding 6 24 16.
  Widget _progressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space6, 6, PgTokens.space6, PgTokens.space4),
      child: Row(
        children: [
          for (var i = 0; i < _totalSteps; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color:
                      i <= _step ? PgTokens.colorPrimary : PgTokens.colorSunken,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Fixed CTA shell: border-top `--border`, bg `--bg-surface`, padding 16 20 (+ SafeArea).
  Widget _footer(RegistrationState state) {
    return Container(
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      padding:
          const EdgeInsets.fromLTRB(20, PgTokens.space4, 20, PgTokens.space4),
      child: PgPrimaryButton(
        label: _ctaLabel,
        busy: state.busy && _step == _totalSteps - 1,
        onPressed: state.busy ? null : _onContinue,
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PgTokens.colorText,
        ),
      );

  // ── Step 1: personal ──────────────────────────────────────────────────────

  Widget _personalStep() {
    // NOTE: v2 UpsertGuardProfileRequest (profile.yaml) has NO name field — name is intentionally
    // omitted here (the backend would reject it). Customer profiles carry full_name; guards don't.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('เพศ / Gender'),
        const SizedBox(height: PgTokens.space2),
        _genderSegment(),
        const SizedBox(height: PgTokens.space4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickDob,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'วันเกิด / Date of birth'),
                  child: Text(_dob ?? 'แตะเพื่อเลือก / Tap to choose',
                      style: TextStyle(
                          color: _dob == null
                              ? PgTokens.colorTextMuted
                              : PgTokens.colorText)),
                ),
              ),
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: TextField(
                controller: _experience,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(
                    labelText: 'ประสบการณ์ (ปี) / Experience (yrs)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: PgTokens.space4),
        TextField(
          controller: _workplace,
          decoration: const InputDecoration(
              labelText: 'ที่ทำงานเดิม / Previous workplace (optional)'),
        ),
      ],
    );
  }

  /// Design `.seg2`: 3 inline options, active = brand border on green-50 with green-800 text.
  Widget _genderSegment() {
    const options = [
      (value: 'male', label: 'ชาย / Male'),
      (value: 'female', label: 'หญิง / Female'),
      (value: 'other', label: 'อื่นๆ / Other'),
    ];
    return Row(
      children: [
        for (final (i, o) in options.indexed) ...[
          if (i > 0) const SizedBox(width: PgTokens.space2),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _gender = o.value),
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: PgTokens.space3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _gender == o.value
                      ? PgTokens.colorGreen50
                      : PgTokens.colorSurface,
                  borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                  border: Border.all(
                    color: _gender == o.value
                        ? PgTokens.colorPrimary
                        : PgTokens.colorBorder,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _gender == o.value
                        ? PgTokens.colorGreen800
                        : PgTokens.colorText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 2: documents ─────────────────────────────────────────────────────

  Widget _documentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in GuardDocKind.values)
          GuardDocRow(
            kind: kind,
            captured: _docs.containsKey(kind),
            onTap: () => _pickDoc(kind),
          ),
      ],
    );
  }

  // ── Step 3: payout account ────────────────────────────────────────────────

  Widget _bankStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _bank,
          isExpanded: true,
          decoration: const InputDecoration(
            label: Text.rich(
              TextSpan(
                text: 'ธนาคาร ',
                children: [
                  TextSpan(
                      text: '*', style: TextStyle(color: PgTokens.colorDanger)),
                ],
              ),
            ),
          ),
          items: [
            for (final b in _banks)
              DropdownMenuItem(
                value: b.value,
                child: Text(b.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _bank = v),
        ),
        const SizedBox(height: PgTokens.space4),
        TextField(
          key: const Key('reg_account_number'),
          controller: _accountNumber,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontFamily: 'IBMPlexMono'),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_maxAccountDigits),
          ],
          decoration: InputDecoration(
            labelText: 'เลขที่บัญชี / Account number',
            errorText: _accountError,
          ),
        ),
        const SizedBox(height: PgTokens.space4),
        TextField(
          controller: _accountName,
          decoration: const InputDecoration(
              labelText: 'ชื่อบัญชี / Account holder name'),
        ),
        const SizedBox(height: PgTokens.space4),
        _fieldLabel('รูปหน้าสมุดบัญชี / Passbook photo'),
        const SizedBox(height: PgTokens.space2),
        _passbookBox(),
      ],
    );
  }

  /// Design passbook capture: 90px tall, dashed-style strong border, sunken bg, camera + hint.
  Widget _passbookBox() {
    final captured = _passbookPath != null;
    return InkWell(
      onTap: _pickPassbook,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: PgTokens.colorSunken,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          border: Border.all(color: PgTokens.colorBorderStrong, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              captured
                  ? Icons.check_circle_outline
                  : Icons.photo_camera_outlined,
              size: 24,
              color: captured ? PgTokens.colorSuccess : PgTokens.colorTextMuted,
            ),
            const SizedBox(height: 6),
            Text(
              captured
                  ? 'เลือกแล้ว / Selected'
                  : 'แตะเพื่อถ่ายรูป / Tap to capture',
              style: const TextStyle(
                fontSize: 12.5,
                color: PgTokens.colorTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 4: review & submit ───────────────────────────────────────────────

  Widget _reviewStep() {
    const valueStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: PgTokens.colorText,
    );
    final genderTh = switch (_gender) {
      'male' => 'ชาย',
      'female' => 'หญิง',
      'other' => 'อื่นๆ',
      _ => '',
    };
    final age = _ageFromIso(_dob);
    final exp = int.tryParse(_experience.text.trim());
    final workplace = _workplace.text.trim();
    final digits = _accountNumber.text.replaceAll(RegExp(r'\D'), '');

    String joinOrDash(List<String> parts) {
      final kept = parts.where((p) => p.isNotEmpty).toList();
      return kept.isEmpty ? '—' : kept.join(' · ');
    }

    final docsComplete = _docs.length == GuardDocKind.values.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _revRow(
            'เพศ / อายุ',
            Text(joinOrDash([genderTh, if (age != null) '$age ปี' else '']),
                style: valueStyle)),
        _revRow(
            'ประสบการณ์',
            Text(joinOrDash([if (exp != null) '$exp ปี' else '', workplace]),
                style: valueStyle)),
        _revRow(
          'เอกสาร',
          Text.rich(
            TextSpan(
              text: '${_docs.length}/${GuardDocKind.values.length}',
              children: [
                if (docsComplete)
                  const TextSpan(
                    text: ' ✓',
                    style: TextStyle(color: PgTokens.colorSuccess),
                  ),
              ],
            ),
            style: valueStyle,
          ),
        ),
        _revRow(
            'ธนาคาร',
            Text(
                joinOrDash([
                  _bank ?? '',
                  if (digits.isNotEmpty) maskAccountNumber(digits) else '',
                ]),
                style: valueStyle)),
      ],
    );
  }

  /// Design `.rev-row`: 11px vertical padding, bottom border, 120px key column.
  Widget _revRow(String label, Widget value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: PgTokens.colorTextMuted,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }
}
