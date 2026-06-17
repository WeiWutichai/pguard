import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/chat_controller.dart';
import '../../core/controllers/chat_format.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/media/chat_media_picker.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import 'widgets/chat_bubble.dart';

/// The real-time conversation. History + live pushes are owned by [ChatController] (the WebSocket
/// lifecycle lives there, NOT in this widget — CLAUDE.md); this screen only renders the message
/// list, autoscrolls on new messages, and hosts the composer. When [readOnly] (booking
/// completed/cancelled) the composer is replaced by a locked banner — the server also rejects
/// writes, so this is UX only. No `Timer.periodic` anywhere.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.acting,
    required this.readOnly,
    this.title,
  });

  final String conversationId;
  final ChatRole acting;
  final bool readOnly;
  final String? title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  bool _attachBusy = false;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  ChatController get _ctrl => ref.read(
      chatControllerProvider(widget.conversationId, widget.acting).notifier);

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _ctrl.send(text);
    _input.clear();
  }

  Future<void> _attach() async {
    if (_attachBusy) return; // one picker/upload at a time
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;

    // 1) Source choice is UI; 2) pick + multipart upload live in the service (testable, no
    // platform channels here); 3) the WS send stays in the controller.
    final source = await showModalBottomSheet<ChatAttachmentSource>(
      context: context,
      builder: (sheet) => _AttachmentSourceSheet(isThai: isThai),
    );
    if (source == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatAttachmentServiceProvider);
    setState(() => _attachBusy = true);
    try {
      final attachment = await service
          .pickAndUpload(widget.conversationId, source, isThai: isThai);
      // A long upload (videos up to 200MB) can outlive this screen — touching `ref`/`_ctrl`
      // after dispose throws, so bail out first (the upload itself completed server-side).
      if (!mounted || attachment == null) return;
      _ctrl.sendAttachment(attachment);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _attachBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider =
        chatControllerProvider(widget.conversationId, widget.acting);
    final async = ref.watch(provider);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    // Autoscroll when a new message lands (initial load or a push). No polling.
    ref.listen(provider, (prev, next) {
      final before = prev?.valueOrNull?.length ?? 0;
      final after = next.valueOrNull?.length ?? 0;
      if (after > before) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(light: true, 
        title: widget.title ?? 'แชท',
        // Design state 3: read-only thread swaps the status line to "job completed".
        subtitle: widget.readOnly
            ? (isThai ? 'งานเสร็จสิ้นแล้ว' : 'Job completed')
            : (isThai ? 'แชท' : 'Chat'),
        showBack: true,
        // Design: 38px counterpart initials avatar in the thread header. PGuardHeader has no
        // leading slot (shared widget — off-limits to extend), so it rides the trailing slot.
        trailing: widget.title == null
            ? null
            : CircleAvatar(
                radius: 19,
                backgroundColor: PgTokens.colorGreen100,
                child: Text(
                  ChatFormat.initials(widget.title),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorGreen800,
                  ),
                ),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => PgErrorState(
                  title: isThai
                      ? 'โหลดข้อความไม่สำเร็จ'
                      : 'Could not load messages',
                  message: e is ApiException ? e.message : null,
                  onRetry: () => ref.invalidate(provider),
                ),
                data: (messages) => messages.isEmpty
                    ? _EmptyBody(isThai: isThai)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            vertical: PgTokens.space3),
                        itemCount: messages.length,
                        itemBuilder: (_, i) {
                          final m = messages[i];
                          final bubble = ChatBubble(
                            message: m,
                            acting: widget.acting,
                            isThai: isThai,
                            counterpartName: widget.title,
                          );
                          // Day separator before the first message of each local day
                          // (design: centered 11px text-faint "วันนี้"/"เมื่อวาน"/short date).
                          if (i > 0 &&
                              ChatFormat.sameLocalDay(
                                  messages[i - 1].createdAt, m.createdAt)) {
                            return bubble;
                          }
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: PgTokens.space1),
                                child: Text(
                                  ChatFormat.dayLabel(m.createdAt,
                                      now: DateTime.now(), thai: isThai),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: PgTokens.colorTextFaint),
                                ),
                              ),
                              bubble,
                            ],
                          );
                        },
                      ),
              ),
            ),
            if (widget.readOnly)
              _LockedBanner(isThai: isThai)
            else
              _Composer(
                input: _input,
                onSend: _send,
                onAttach: _attachBusy ? null : _attach,
                isThai: isThai,
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: where the attachment comes from (camera photo / gallery photo / video).
/// Design sheet-opt rows: grab handle, 42px sunken icon circle, 15px w600 label.
class _AttachmentSourceSheet extends StatelessWidget {
  const _AttachmentSourceSheet({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle: ~40×4, border colour, fully rounded.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(
                top: PgTokens.space3, bottom: PgTokens.space2),
            decoration: BoxDecoration(
              color: PgTokens.colorBorder,
              borderRadius: BorderRadius.circular(PgTokens.radiusFull),
            ),
          ),
          _SheetOption(
            icon: Icons.photo_camera_outlined,
            label: isThai ? 'ถ่ายรูป' : 'Take a photo',
            onTap: () =>
                Navigator.pop(context, ChatAttachmentSource.cameraPhoto),
          ),
          _SheetOption(
            icon: Icons.photo_library_outlined,
            label: isThai ? 'เลือกรูปจากคลัง' : 'Choose a photo',
            onTap: () =>
                Navigator.pop(context, ChatAttachmentSource.galleryPhoto),
          ),
          _SheetOption(
            icon: Icons.video_library_outlined,
            label: isThai ? 'เลือกวิดีโอจากคลัง' : 'Choose a video',
            onTap: () =>
                Navigator.pop(context, ChatAttachmentSource.galleryVideo),
          ),
        ],
      ),
    );
  }
}

/// One design .sheet-opt row (icon circle + semibold label, 16px 24px padding).
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
      leading: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: PgTokens.colorSunken,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: PgTokens.colorText),
      ),
      title: Text(
        label,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorText),
      ),
      onTap: onTap,
    );
  }
}

/// Empty conversation — same icon + title + subtitle hierarchy as the sibling
/// chat-list/notification empty states (cross-state hero pattern).
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined,
              size: 48, color: PgTokens.colorTextFaint),
          const SizedBox(height: PgTokens.space3),
          Text(
            isThai ? 'ยังไม่มีข้อความ' : 'No messages yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai ? 'เริ่มพิมพ์ได้เลย' : 'Say hello',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ],
      ),
    );
  }
}

/// Read-only banner shown instead of the composer when the booking is completed/cancelled.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: const BoxDecoration(
        color: PgTokens.colorSunken,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline,
                size: 16, color: PgTokens.colorTextMuted),
            const SizedBox(width: PgTokens.space2),
            Flexible(
              child: Text(
                isThai
                    ? 'งานสิ้นสุดแล้ว ไม่สามารถส่งข้อความได้'
                    : 'Job ended — messaging is disabled',
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.onSend,
    required this.onAttach,
    required this.isThai,
  });

  final TextEditingController input;
  final VoidCallback onSend;

  /// Disabled (null) while a pick/upload is already in flight.
  final VoidCallback? onAttach;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Design: 10px 14px composer padding, 9px gaps (non-token design metrics).
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Design .att: 38px sunken circle with a muted icon.
            IconButton.filled(
              onPressed: onAttach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              style: IconButton.styleFrom(
                backgroundColor: PgTokens.colorSunken,
                foregroundColor: PgTokens.colorTextMuted,
                fixedSize: const Size(38, 38),
              ),
              tooltip: isThai ? 'แนบรูป/วิดีโอ' : 'Attach image/video',
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                // Design .box: fully-rounded borderless pill on the sunken bg.
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: PgTokens.colorSunken,
                  hintText: isThai ? 'พิมพ์ข้อความ…' : 'Type a message…',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: PgTokens.space4, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: PgTokens.colorPrimary,
                foregroundColor: Colors.white,
                fixedSize: const Size(40, 40),
              ),
              tooltip: isThai ? 'ส่ง' : 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
