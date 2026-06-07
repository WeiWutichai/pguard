import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/chat_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
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

  ChatController get _ctrl => ref
      .read(chatControllerProvider(widget.conversationId, widget.acting).notifier);

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _ctrl.send(text);
    _input.clear();
  }

  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final service = ref.read(chatAttachmentServiceProvider);
    try {
      final attachment = await service.pickAndUpload(widget.conversationId);
      if (attachment == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(isThai
              ? 'การแนบไฟล์ยังไม่พร้อมใช้งาน'
              : 'Attachments are not available yet'),
        ));
        return;
      }
      _ctrl.sendAttachment(attachment);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
      appBar: PGuardHeader(
        title: widget.title ?? 'แชท',
        subtitle: 'Chat',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PgTokens.space6),
                    child: Text(
                      e is ApiException
                          ? e.message
                          : 'โหลดข้อความไม่สำเร็จ / Could not load messages',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: PgTokens.colorTextMuted),
                    ),
                  ),
                ),
                data: (messages) => messages.isEmpty
                    ? _EmptyBody(isThai: isThai)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            vertical: PgTokens.space3),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => ChatBubble(
                          message: messages[i],
                          acting: widget.acting,
                          isThai: isThai,
                        ),
                      ),
              ),
            ),
            if (widget.readOnly)
              _LockedBanner(isThai: isThai)
            else
              _Composer(
                input: _input,
                onSend: _send,
                onAttach: _attach,
                isThai: isThai,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isThai
            ? 'ยังไม่มีข้อความ — เริ่มพิมพ์ได้เลย'
            : 'No messages yet — say hello',
        style: const TextStyle(color: PgTokens.colorTextMuted),
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
                size: 18, color: PgTokens.colorTextMuted),
            const SizedBox(width: PgTokens.space2),
            Flexible(
              child: Text(
                isThai
                    ? 'งานสิ้นสุดแล้ว ไม่สามารถส่งข้อความได้'
                    : 'Job ended. Messaging is disabled.',
                style: const TextStyle(color: PgTokens.colorTextMuted),
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
  final VoidCallback onAttach;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space2, vertical: PgTokens.space2),
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onAttach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: PgTokens.colorPrimary,
              tooltip: isThai ? 'แนบรูป/วิดีโอ' : 'Attach image/video',
            ),
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: isThai ? 'พิมพ์ข้อความ…' : 'Type a message…',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: PgTokens.space3, vertical: PgTokens.space2),
                ),
              ),
            ),
            const SizedBox(width: PgTokens.space1),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: PgTokens.colorPrimary,
                foregroundColor: Colors.white,
              ),
              tooltip: isThai ? 'ส่ง' : 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
