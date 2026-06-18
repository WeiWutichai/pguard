import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_documents_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/media/document_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';

/// Post-approval guard documents: an approved, logged-in guard uploads photos of their six
/// credentials (`POST /profile/guard/{user_id}/documents`, own-only). Status is the server's
/// truth (probed on open, no polling); a stored image shows its presigned thumbnail. Expiry
/// dates are captured at registration, not here (see [GuardDocumentsController]).
class GuardDocumentsScreen extends ConsumerWidget {
  const GuardDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(guardDocumentsControllerProvider);
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'เอกสารของฉัน' : 'My documents',
        subtitle: isThai ? 'อัปโหลดเอกสารประจำตัว' : 'Upload your credentials',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title:
                isThai ? 'โหลดเอกสารไม่สำเร็จ' : 'Could not load documents',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(guardDocumentsControllerProvider),
          ),
          data: (docs) => ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              _Intro(isThai: isThai, uploadedCount: docs.uploadedCount),
              const SizedBox(height: PgTokens.space4),
              Container(
                decoration: BoxDecoration(
                  color: PgTokens.colorSurface,
                  borderRadius: BorderRadius.circular(PgTokens.radius2xl),
                  border: Border.all(color: PgTokens.colorBorder),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: PgTokens.space4, vertical: PgTokens.space1),
                child: Column(
                  children: [
                    for (final c in GuardCredential.values)
                      _DocRow(
                        slot: docs.slotFor(c),
                        isThai: isThai,
                        isLast: c == GuardCredential.values.last,
                        onTap: () => _pickAndUpload(context, ref, c, isThai),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Camera-or-gallery sheet → real picker → upload. Mirrors the registration capture sheet so the
  /// guard form and this screen share one source-selection UX.
  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    GuardCredential credential,
    bool isThai,
  ) async {
    final source = await showModalBottomSheet<DocSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(isThai ? 'ถ่ายรูป' : 'Take photo'),
              onTap: () => Navigator.pop(ctx, DocSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(isThai ? 'เลือกจากคลัง' : 'Choose from gallery'),
              onTap: () => Navigator.pop(ctx, DocSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return; // user dismissed the sheet
    final path = await ref.read(documentPickerProvider).pick(source);
    if (path == null) return; // user cancelled the picker
    if (!context.mounted) return; // screen popped during the OS picker — don't touch ref
    final err = await ref
        .read(guardDocumentsControllerProvider.notifier)
        .upload(credential, path);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

/// The honest intro: what this screen is for + a non-fabricated progress count.
class _Intro extends StatelessWidget {
  const _Intro({required this.isThai, required this.uploadedCount});

  final bool isThai;
  final int uploadedCount;

  @override
  Widget build(BuildContext context) {
    final total = GuardCredential.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isThai
              ? 'อัปโหลดรูปเอกสารประจำตัวเพื่อให้แอดมินตรวจสอบ'
              : 'Upload photos of your credentials for admin verification.',
          style: const TextStyle(
              fontSize: 13, color: PgTokens.colorTextMuted, height: 1.4),
        ),
        const SizedBox(height: PgTokens.space2),
        Text(
          isThai
              ? 'อัปโหลดแล้ว $uploadedCount จาก $total'
              : 'Uploaded $uploadedCount of $total',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorTextStrong,
          ),
        ),
      ],
    );
  }
}

/// One credential row: thumbnail + name/status + a (re)upload action, with a divider unless last.
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.slot,
    required this.isThai,
    required this.isLast,
    required this.onTap,
  });

  final DocSlot slot;
  final bool isThai;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = slot.credential;
    return InkWell(
      // Don't accept a new tap while an upload for this row is in flight.
      onTap: slot.busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PgTokens.space3),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: PgTokens.colorBorder)),
        ),
        child: Row(
          children: [
            _Thumb(uploaded: slot.uploaded, downloadUrl: slot.downloadUrl),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.label(isThai),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slot.uploaded
                        ? (isThai ? 'อัปโหลดแล้ว' : 'Uploaded')
                        : (isThai ? 'ยังไม่อัปโหลด' : 'Not uploaded'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: slot.uploaded
                          ? PgTokens.colorSuccess
                          : PgTokens.colorTextMuted,
                    ),
                  ),
                  if (slot.error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      slot.error!,
                      style: const TextStyle(
                          fontSize: 11.5, color: PgTokens.colorDanger),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: PgTokens.space2),
            _Trailing(slot: slot, isThai: isThai),
          ],
        ),
      ),
    );
  }
}

/// Trailing action: a spinner while uploading, else "Change" (uploaded) or "Upload".
class _Trailing extends StatelessWidget {
  const _Trailing({required this.slot, required this.isThai});

  final DocSlot slot;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    if (slot.busy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Text(
      slot.uploaded
          ? (isThai ? 'เปลี่ยน' : 'Change')
          : (isThai ? 'อัปโหลด' : 'Upload'),
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: PgTokens.colorPrimary,
      ),
    );
  }
}

/// 64×48 thumbnail: the stored image (presigned URL) when uploaded; a strong-bordered "+" box when
/// not. If the presigned image fails to load (expired/offline) it degrades to a green check rather
/// than a broken-image glyph.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.uploaded, required this.downloadUrl});

  final bool uploaded;
  final String? downloadUrl;

  static const double _w = 64;
  static const double _h = 48;

  @override
  Widget build(BuildContext context) {
    if (!uploaded) {
      return Container(
        width: _w,
        height: _h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          border: Border.all(color: PgTokens.colorBorderStrong, width: 2),
        ),
        child: const Icon(Icons.add, size: 20, color: PgTokens.colorTextFaint),
      );
    }
    final check = Container(
      width: _w,
      height: _h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PgTokens.colorGreen100, PgTokens.colorGreen200],
        ),
      ),
      child: const Icon(Icons.check, size: 20, color: PgTokens.colorGreen800),
    );
    final url = downloadUrl;
    if (url == null) return check;
    return ClipRRect(
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: Image.network(
        url,
        width: _w,
        height: _h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => check,
      ),
    );
  }
}
