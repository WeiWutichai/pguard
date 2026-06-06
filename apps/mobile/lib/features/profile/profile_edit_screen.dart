import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

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
  final _gender = TextEditingController();
  final _dob = TextEditingController();
  final _experience = TextEditingController();
  final _workplace = TextEditingController();
  final _bankName = TextEditingController();
  final _accountName = TextEditingController();
  final _newAccountNumber = TextEditingController();

  bool _saving = false;
  String? _error;
  late final UserProfile? _profile =
      ref.read(profileControllerProvider).valueOrNull;

  @override
  void initState() {
    super.initState();
    final p = _profile;
    if (p != null) {
      _fullName.text = p.fullName ?? '';
      _address.text = p.address ?? '';
      _gender.text = p.gender ?? '';
      _dob.text = p.dateOfBirth ?? '';
      _experience.text = p.yearsOfExperience?.toString() ?? '';
      _workplace.text = p.previousWorkplace ?? '';
      _bankName.text = p.bankName ?? '';
      _accountName.text = p.accountName ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _address,
      _gender,
      _dob,
      _experience,
      _workplace,
      _bankName,
      _accountName,
      _newAccountNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? trimOrNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final String? err;
    if (p.isGuard) {
      err = await ref.read(profileControllerProvider.notifier).save(
            gender: trimOrNull(_gender),
            dateOfBirth: trimOrNull(_dob),
            yearsOfExperience: int.tryParse(_experience.text.trim()),
            previousWorkplace: trimOrNull(_workplace),
            bankName: trimOrNull(_bankName),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกแล้ว / Saved')),
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
    final p = _profile;
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'แก้ไขโปรไฟล์',
        subtitle: 'Edit profile',
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
                            label: 'เบอร์โทร (เข้าสู่ระบบ) / Phone',
                            value: p.phone ?? '—'),
                        const SizedBox(height: PgTokens.space4),
                        if (p.isGuard) ..._guardFields() else ..._customerFields(),
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
                        label: 'บันทึก / Save',
                        busy: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _customerFields() => [
        _Field(label: 'ชื่อ-นามสกุล / Full name', controller: _fullName),
        const SizedBox(height: PgTokens.space3),
        _Field(label: 'ที่อยู่ / Address', controller: _address, maxLines: 2),
      ];

  List<Widget> _guardFields() => [
        _Field(label: 'เพศ / Gender', controller: _gender),
        const SizedBox(height: PgTokens.space3),
        _Field(
            label: 'วันเกิด (ปปปป-ดด-วว) / Date of birth',
            controller: _dob,
            hint: '1995-05-20'),
        const SizedBox(height: PgTokens.space3),
        _Field(
          label: 'ประสบการณ์ (ปี) / Experience (years)',
          controller: _experience,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: PgTokens.space3),
        _Field(label: 'ที่ทำงานก่อนหน้า / Previous workplace', controller: _workplace),
        const SizedBox(height: PgTokens.space3),
        _Field(label: 'ธนาคาร / Bank', controller: _bankName),
        const SizedBox(height: PgTokens.space3),
        _Field(label: 'ชื่อบัญชี / Account name', controller: _accountName),
        const SizedBox(height: PgTokens.space3),
        if ((_profile?.accountNumberMasked ?? '').isNotEmpty)
          _ReadonlyField(
              label: 'เลขบัญชีปัจจุบัน / Current account',
              value: _profile!.accountNumberMasked!),
        const SizedBox(height: PgTokens.space3),
        _Field(
          label: 'เปลี่ยนเลขบัญชี (ถ้าต้องการ) / New account number',
          controller: _newAccountNumber,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ];
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
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
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
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space3, vertical: 14),
          decoration: BoxDecoration(
            color: PgTokens.colorSunken,
            borderRadius: BorderRadius.circular(PgTokens.radiusMd),
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
