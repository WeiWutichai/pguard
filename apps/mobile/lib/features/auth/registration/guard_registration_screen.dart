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

/// Guard profile form — multi-step (`Stepper`): personal → documents (REAL `image_picker`) → bank.
/// Submits the JSON fields the v2 contract accepts (`UpsertGuardProfileRequest`:
/// gender/dob/experience/workplace/bank) to `POST /profile/guard` with the single-use
/// `profile_token`. The bank account number is digits-only; it's sent in FULL to the backend but
/// the controller masks it before persisting any local summary (PDPA).
///
/// Document images are captured with the real picker (an onboarding requirement) and validated
/// client-side, but NOT uploaded: v2 `profile.yaml` has no document-upload endpoint yet, so the
/// step is non-blocking and the captured paths are held for the future endpoint (PR-flagged).
class GuardRegistrationScreen extends ConsumerStatefulWidget {
  const GuardRegistrationScreen({super.key});

  @override
  ConsumerState<GuardRegistrationScreen> createState() =>
      _GuardRegistrationScreenState();
}

class _GuardRegistrationScreenState
    extends ConsumerState<GuardRegistrationScreen> {
  static const int _minAccountDigits = 10;
  static const int _maxAccountDigits = 15;

  int _step = 0;

  // Personal
  String? _gender;
  String? _dob; // ISO yyyy-MM-dd
  final _experience = TextEditingController();
  final _workplace = TextEditingController();

  // Documents (real picker) — kind → file path.
  final Map<GuardDocKind, String> _docs = {};

  // Bank
  final _bankName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  String? _accountError;

  @override
  void dispose() {
    _experience.dispose();
    _workplace.dispose();
    _bankName.dispose();
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
    if (digits.length < _minAccountDigits || digits.length > _maxAccountDigits) {
      setState(() => _accountError =
          'เลขบัญชี $_minAccountDigits–$_maxAccountDigits หลัก / Account must be $_minAccountDigits–$_maxAccountDigits digits');
      return false;
    }
    setState(() => _accountError = null);
    return true;
  }

  Future<void> _pickDoc(GuardDocKind kind) async {
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
    if (source == null) return;
    final path = await ref.read(documentPickerProvider).pick(source);
    if (path != null && mounted) {
      setState(() => _docs[kind] = path);
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
    } else {
      await _submit();
    }
  }

  void _onCancel() {
    if (_step > 0) setState(() => _step -= 1);
  }

  Future<void> _submit() async {
    // Re-validate experience here too: onStepTapped lets a user jump straight to the bank step,
    // bypassing the step 0→1 check, so catch an out-of-range value client-side (not via a 400).
    final expErr = _validExperience();
    if (expErr != null) {
      setState(() => _step = 0);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(expErr)));
      return;
    }
    if (!_bankIsValid()) return;
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final ok = await ctrl.submitGuardProfile(
      gender: _gender,
      dateOfBirth: _dob,
      yearsOfExperience: int.tryParse(_experience.text.trim()),
      previousWorkplace: _workplace.text,
      bankName: _bankName.text,
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationControllerProvider);

    return Scaffold(
      appBar: const PGuardHeader(
        title: 'ข้อมูลเจ้าหน้าที่',
        subtitle: 'Guard profile',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stepper(
                currentStep: _step,
                type: StepperType.vertical,
                onStepContinue: state.busy ? null : _onContinue,
                onStepCancel: state.busy ? null : _onCancel,
                onStepTapped: state.busy ? null : (s) => setState(() => _step = s),
                // Render controls only for the ACTIVE step (a vertical Stepper otherwise keeps
                // every step's controls in the tree → duplicate buttons).
                controlsBuilder: (context, details) {
                  if (details.stepIndex != _step) {
                    return const SizedBox.shrink();
                  }
                  final isLast = details.stepIndex == 2;
                  return Padding(
                    padding: const EdgeInsets.only(top: PgTokens.space4),
                    child: Row(
                      children: [
                        Expanded(
                          child: PgPrimaryButton(
                            label:
                                isLast ? 'บันทึกและส่ง / Submit' : 'ถัดไป / Next',
                            busy: state.busy && isLast,
                            onPressed:
                                state.busy ? null : details.onStepContinue,
                          ),
                        ),
                        if (details.stepIndex > 0) ...[
                          const SizedBox(width: PgTokens.space3),
                          TextButton(
                            onPressed:
                                state.busy ? null : details.onStepCancel,
                            child: const Text('ย้อนกลับ / Back'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                steps: [
                  Step(
                    title: const Text('ข้อมูลส่วนตัว / Personal'),
                    isActive: _step >= 0,
                    state: _step > 0 ? StepState.complete : StepState.indexed,
                    content: _personalStep(),
                  ),
                  Step(
                    title: const Text('เอกสาร / Documents'),
                    isActive: _step >= 1,
                    state: _step > 1 ? StepState.complete : StepState.indexed,
                    content: _documentsStep(),
                  ),
                  Step(
                    title: const Text('บัญชีธนาคาร / Bank'),
                    isActive: _step >= 2,
                    state: StepState.indexed,
                    content: _bankStep(),
                  ),
                ],
              ),
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(PgTokens.space4),
                child: Text(state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _personalStep() {
    // NOTE: v2 UpsertGuardProfileRequest (profile.yaml) has NO name field — name is intentionally
    // omitted here (the backend would reject it). Customer profiles carry full_name; guards don't.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: const InputDecoration(labelText: 'เพศ / Gender'),
          items: const [
            DropdownMenuItem(value: 'male', child: Text('ชาย / Male')),
            DropdownMenuItem(value: 'female', child: Text('หญิง / Female')),
            DropdownMenuItem(value: 'other', child: Text('อื่นๆ / Other')),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: PgTokens.space4),
        InkWell(
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
        const SizedBox(height: PgTokens.space4),
        TextField(
          controller: _experience,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: const InputDecoration(
              labelText: 'ปีประสบการณ์ / Years of experience'),
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

  Widget _documentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'ถ่ายหรือเลือกรูปเอกสาร · การอัปโหลดจะเปิดให้เร็วๆ นี้\n'
          'Capture or pick documents · upload arrives with the backend endpoint',
          style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 12),
        ),
        const SizedBox(height: PgTokens.space3),
        for (final kind in GuardDocKind.values)
          Padding(
            padding: const EdgeInsets.only(bottom: PgTokens.space2),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: PgTokens.space3),
              leading: Icon(
                _docs.containsKey(kind)
                    ? Icons.check_circle
                    : Icons.upload_file_outlined,
                color: _docs.containsKey(kind)
                    ? PgTokens.colorSuccess
                    : PgTokens.colorTextMuted,
              ),
              title: Text('${kind.labelTh} · ${kind.labelEn}',
                  style: const TextStyle(fontSize: 14)),
              subtitle: _docs.containsKey(kind)
                  ? const Text('เลือกแล้ว / Selected')
                  : null,
              trailing: TextButton(
                onPressed: () => _pickDoc(kind),
                child: Text(_docs.containsKey(kind)
                    ? 'เปลี่ยน / Change'
                    : 'เลือก / Pick'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bankStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _bankName,
          decoration:
              const InputDecoration(labelText: 'ธนาคาร / Bank name'),
        ),
        const SizedBox(height: PgTokens.space4),
        TextField(
          key: const Key('reg_account_number'),
          controller: _accountNumber,
          keyboardType: TextInputType.number,
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
      ],
    );
  }
}
