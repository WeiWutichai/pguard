import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/models/profile.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Edit the caller's profile. Customer edits name + address; guard edits the guard-profile
/// fields. Phone is READ-ONLY (login identifier). Saves via the upsert in [ProfileController].
class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  // Customer
  final _fullName = TextEditingController();
  final _address = TextEditingController();
  // Guard
  String? _gender; // dropdown (male|female|other)
  final _dob = TextEditingController();
  final _experience = TextEditingController();
  final _workplace = TextEditingController();
  String? _bankName; // dropdown (Thai bank name)
  final _accountName = TextEditingController();
  final _newAccountNumber = TextEditingController();

  // Dropdown options — reuse the registration form's lists so edit + register agree. `value` is the
  // stored code (locale-independent: male/female/other; the Thai bank name); `label` is localized.
  static List<({String value, String label})> _genders(bool isThai) => [
        (value: 'male', label: isThai ? 'ชาย' : 'Male'),
        (value: 'female', label: isThai ? 'หญิง' : 'Female'),
        (value: 'other', label: isThai ? 'อื่นๆ' : 'Other'),
      ];
  static List<({String value, String label})> _banks(bool isThai) => [
        (
          value: 'ธนาคารกสิกรไทย',
          label: isThai ? 'ธนาคารกสิกรไทย' : 'Kasikornbank'
        ),
        (
          value: 'ธนาคารไทยพาณิชย์',
          label: isThai ? 'ธนาคารไทยพาณิชย์' : 'Siam Commercial Bank'
        ),
        (
          value: 'ธนาคารกรุงเทพ',
          label: isThai ? 'ธนาคารกรุงเทพ' : 'Bangkok Bank'
        ),
        (
          value: 'ธนาคารกรุงไทย',
          label: isThai ? 'ธนาคารกรุงไทย' : 'Krung Thai Bank'
        ),
      ];

  bool _saving = false;
  bool _seeded = false;
  String? _error;

  /// Seed the text fields once, when the profile first becomes available.
  void _seed(UserProfile p) {
    if (_seeded) return;
    _fullName.text = p.fullName ?? '';
    _address.text = p.address ?? '';
    // Coerce to null when the stored value isn't a dropdown option (DropdownButtonFormField asserts
    // on an initialValue with no matching item — e.g. a legacy free-typed bank/gender).
    _gender =
        const ['male', 'female', 'other'].contains(p.gender) ? p.gender : null;
    _dob.text = p.dateOfBirth ?? '';
    _experience.text = p.yearsOfExperience?.toString() ?? '';
    _workplace.text = p.previousWorkplace ?? '';
    _bankName =
        _banks(true).any((b) => b.value == p.bankName) ? p.bankName : null;
    _accountName.text = p.accountName ?? '';
    _seeded = true;
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _address,
      _dob,
      _experience,
      _workplace,
      _accountName,
      _newAccountNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(UserProfile p) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    String? trimOrNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final String? err;
    if (p.isGuard) {
      err = await ref.read(profileControllerProvider.notifier).save(
            gender: _gender,
            dateOfBirth: trimOrNull(_dob),
            yearsOfExperience: int.tryParse(_experience.text.trim()),
            previousWorkplace: trimOrNull(_workplace),
            bankName: _bankName,
            accountName: trimOrNull(_accountName),
            // Only send a NEW account number — never echo the masked value back.
            accountNumber: trimOrNull(_newAccountNumber),
          );
    } else {
      err = await ref.read(profileControllerProvider.notifier).save(
            fullName: trimOrNull(_fullName),
            address: trimOrNull(_address),
          );
    }
    if (!mounted) return;
    if (err == null) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isThai ? 'บันทึกแล้ว' : 'Saved')),
      );
      context.pop();
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final p = ref.watch(profileControllerProvider).valueOrNull;
    if (p != null) _seed(p);
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'แก้ไขโปรไฟล์' : 'Edit profile',
        subtitle: isThai ? 'แก้ไขข้อมูลโปรไฟล์ของคุณ' : 'Edit profile',
        showBack: true,
      ),
      body: SafeArea(
        child: p == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(PgTokens.space4),
                      children: [
                        _ReadonlyField(
                            label: isThai ? 'เบอร์โทร (เข้าสู่ระบบ)' : 'Phone',
                            value: p.phone ?? '—'),
                        const SizedBox(height: PgTokens.space4),
                        if (p.isGuard)
                          ..._guardFields(p, isThai)
                        else
                          ..._customerFields(isThai),
                        if (_error != null) ...[
                          const SizedBox(height: PgTokens.space3),
                          Text(_error!,
                              style:
                                  const TextStyle(color: PgTokens.colorDanger)),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(PgTokens.space4),
                    decoration: const BoxDecoration(
                      color: PgTokens.colorSurface,
                      border:
                          Border(top: BorderSide(color: PgTokens.colorBorder)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: PgPrimaryButton(
                        label: isThai ? 'บันทึก' : 'Save',
                        busy: _saving,
                        onPressed: _saving ? null : () => _save(p),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _customerFields(bool isThai) => [
        _Field(
            label: isThai ? 'ชื่อ-นามสกุล' : 'Full name',
            controller: _fullName),
        const SizedBox(height: PgTokens.space3),
        _Field(
            label: isThai ? 'ที่อยู่' : 'Address',
            controller: _address,
            maxLines: 2),
      ];

  List<Widget> _guardFields(UserProfile p, bool isThai) => [
        _DropdownField(
          label: isThai ? 'เพศ' : 'Gender',
          value: _gender,
          items: _genders(isThai),
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: PgTokens.space3),
        _Field(
            label: isThai ? 'วันเกิด (ปปปป-ดด-วว)' : 'Date of birth',
            controller: _dob,
            hint: '1995-05-20'),
        const SizedBox(height: PgTokens.space3),
        _Field(
          label: isThai ? 'ประสบการณ์ (ปี)' : 'Experience (years)',
          controller: _experience,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: PgTokens.space3),
        _Field(
            label: isThai ? 'ที่ทำงานก่อนหน้า' : 'Previous workplace',
            controller: _workplace),
        const SizedBox(height: PgTokens.space3),
        _DropdownField(
          label: isThai ? 'ธนาคาร' : 'Bank',
          value: _bankName,
          items: _banks(isThai),
          onChanged: (v) => setState(() => _bankName = v),
        ),
        const SizedBox(height: PgTokens.space3),
        _Field(
            label: isThai ? 'ชื่อบัญชี' : 'Account name',
            controller: _accountName),
        const SizedBox(height: PgTokens.space3),
        if ((p.accountNumberMasked ?? '').isNotEmpty)
          _ReadonlyField(
              label: isThai ? 'เลขบัญชีปัจจุบัน' : 'Current account',
              value: p.accountNumberMasked!),
        const SizedBox(height: PgTokens.space3),
        _Field(
          label: isThai ? 'เปลี่ยนเลขบัญชี (ถ้าต้องการ)' : 'New account number',
          controller: _newAccountNumber,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ];
}

/// A labelled dropdown styled like [_Field] (label above the control). Used for the guard profile's
/// gender + bank fields so they're PICKED from a fixed list, not free-typed.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<({String value, String label})> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space1),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: [
            for (final it in items)
              DropdownMenuItem(
                value: it.value,
                child: Text(it.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space1),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space1),
        Container(
          width: double.infinity,
          // Design .minput: 12px 14px padding; read-only shares the editable
          // inputs' radius (themed inputs use radiusXl).
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: PgTokens.space3),
          decoration: BoxDecoration(
            color: PgTokens.colorSunken,
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value,
                    style: const TextStyle(color: PgTokens.colorTextMuted)),
              ),
              const Icon(Icons.lock_outline,
                  size: 16, color: PgTokens.colorTextFaint),
            ],
          ),
        ),
      ],
    );
  }
}
