import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/call_controller.dart';
import '../../core/controllers/chat_controller.dart';
import '../../core/controllers/chat_format.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/media/chat_media_picker.dart';
import '../../core/models/call.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_skeleton.dart';
import '../../widgets/pguard_header.dart';
import '../call/call_routes.dart';
import 'widgets/chat_bubble.dart';

/// The real-time conversation. History + live pushes are owned by [ChatController] (the WebSocket
/// lifecycle lives there, NOT in this widget — CLAUDE.md); this screen only renders the message
/// list, autoscrolls on new messages, and hosts the composer. When read-only (booking
/// completed/cancelled) the composer is replaced by a locked banner — the server also rejects
/// writes, so this is UX only. No `Timer.periodic` anywhere.
///
/// Read-only is SELF-VERIFIED: the navigation-time [readOnly] flag is only a hint (it goes stale
/// when the booking closes while the thread is open, and the push-notification entry hardcodes
/// `false`), so the screen ORs it with the server-resolved [chatServerClosedProvider] — and a
/// live send rejected with `code == "read_only"` flips that provider, locking the composer
/// reactively (plus a snackbar via [chatSendErrorsProvider], so no rejection vanishes silently).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.acting,
    required this.readOnly,
    this.title,
    this.bookingId,
    this.callable = false,
  });

  final String conversationId;
  final ChatRole acting;
  final bool readOnly;
  final String? title;

  /// The linked booking (`request_id`) the in-thread call action calls within. Null when the
  /// thread was opened without booking context (deep link / chat list) → no call action.
  final String? bookingId;

  /// Whether a voice call is allowed RIGHT NOW (booking in `accepted`/`en_route`/`arrived` with a
  /// guard assigned — see [BookingLifecycle.isCallable]). When false the call action is shown but
  /// DISABLED with a hint, never routing the user into a guaranteed "not active for calling" error.
  final bool callable;

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

  /// Start a voice call to the counterpart for this booking and open the call screen. Only
  /// reachable when [ChatScreen.callable] (the calling service would otherwise 409); the disabled
  /// state is handled in [_CallAction], so this is the happy-path-only handler.
  void _startCall() {
    final bookingId = widget.bookingId;
    if (bookingId == null) return;
    final router = GoRouter.of(context);
    ref.read(callControllerProvider.notifier).startOutgoing(
          bookingId: bookingId,
          type: CallType.audio,
        );
    router.push(CallRoutes.outgoing());
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // Clear the composer ONLY when the frame reached a live socket. If the WS is down the send is
    // dropped (the bubble only ever comes from the server echo), so keep the text and tell the user
    // it didn't go — a lost frame used to erase the message from both the composer and the thread
    // with no error (deep-review).
    final sent = _ctrl.send(text);
    if (sent) {
      _input.clear();
    } else {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isThai
            ? 'ส่งข้อความไม่สำเร็จ — กำลังเชื่อมต่อใหม่ ลองอีกครั้ง'
            : "Couldn't send — reconnecting, please try again"),
      ));
    }
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
      // The attachment is already persisted; only the chat message frame rides the WS. If the
      // socket is down that frame drops, so surface it rather than leaving the user to wonder why
      // the image never appeared.
      if (!_ctrl.sendAttachment(attachment)) {
        messenger.showSnackBar(SnackBar(
          content: Text(isThai
              ? 'ส่งไฟล์ไม่สำเร็จ — กำลังเชื่อมต่อใหม่ ลองอีกครั้ง'
              : "Couldn't send — reconnecting, please try again"),
        ));
      }
    } on ApiException catch (e) {
      // A read-only conversation (booking completed/cancelled while the thread was open) makes the
      // chat service reject the upload with 409 — surface the localized "job ended" line, NOT the
      // server's English text or a generic transport error. Any other error shows its own message.
      final text = e.isConflict
          ? ChatReadOnly.sendBlockedMessage(isThai: isThai)
          : e.message;
      messenger.showSnackBar(SnackBar(content: Text(text)));
      // A 409 upload rejection is the SAME read-only signal as a rejected WS text send — latch
      // the composer closed so the user can't keep re-attaching into a dead thread (mirrors the
      // WS `code == "read_only"` path). Only the upload endpoint's read-only gate 409s here.
      if (e.isConflict && mounted) {
        ref
            .read(chatServerClosedProvider(widget.conversationId, widget.acting)
                .notifier)
            .markClosed();
      }
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

    // SELF-VERIFIED read-only: the navigation flag OR the server's own answer (resolved from the
    // conversations list + flipped live by a rejected send). Short-circuit keeps an already-known
    // read-only entry from spending a fetch on re-verification; while unresolved (loading/error)
    // only the navigation flag applies — the server still rejects writes either way.
    final effectiveReadOnly = widget.readOnly ||
        (ref
                .watch(chatServerClosedProvider(
                    widget.conversationId, widget.acting))
                .valueOrNull ??
            false);

    // Autoscroll when a new message lands (initial load or a push). No polling.
    ref.listen(provider, (prev, next) {
      final before = prev?.valueOrNull?.length ?? 0;
      final after = next.valueOrNull?.length ?? 0;
      if (after > before) _scrollToBottom();
    });

    // A send the server REFUSED must not vanish silently: read-only rejections show the existing
    // localized "job ended" line (the composer lock itself comes from chatServerClosedProvider,
    // flipped by the controller); any other/legacy error frame (no `code`) surfaces its
    // client-safe message as a generic snackbar.
    ref.listen(chatSendErrorsProvider(widget.conversationId, widget.acting),
        (prev, next) {
      final error = next.valueOrNull;
      if (error == null) return;
      final text = error.isReadOnly
          ? ChatReadOnly.sendBlockedMessage(isThai: isThai)
          : (error.message.isNotEmpty
              ? error.message
              : (isThai ? 'ส่งข้อความไม่สำเร็จ' : 'Message could not be sent'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });

    // The counterpart label: the name when known, else a generic role-aware fallback (the v2
    // Booking model carries no counterpart name, so a booking-launched thread has none until the
    // chat-list resupplies it — display-only gap, never a blank "?" header).
    final hasName = (widget.title ?? '').trim().isNotEmpty;
    final counterpartLabel = hasName
        ? widget.title!
        : (widget.acting == ChatRole.guard
            ? (isThai ? 'ลูกค้า' : 'Customer')
            : (isThai ? 'เจ้าหน้าที่' : 'Security guard'));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: counterpartLabel,
        // Design state 3: read-only thread swaps the status line to "job completed".
        subtitle: effectiveReadOnly
            ? (isThai ? 'งานเสร็จสิ้นแล้ว' : 'Job completed')
            : (isThai ? 'แชท' : 'Chat'),
        showBack: true,
        // Design: 38px counterpart initials avatar in the thread header + (when a call is
        // possible) a call action. PGuardHeader has no leading slot (shared widget — off-limits to
        // extend), so both ride the single trailing slot.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.bookingId != null) ...[
              _CallAction(
                enabled: widget.callable && !effectiveReadOnly,
                isThai: isThai,
                onCall: _startCall,
              ),
              const SizedBox(width: PgTokens.space2),
            ],
            CircleAvatar(
              radius: 19,
              backgroundColor: PgTokens.colorGreen100,
              child: hasName
                  ? Text(
                      ChatFormat.initials(widget.title),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorGreen800,
                      ),
                    )
                  : const Icon(Icons.person,
                      size: 20, color: PgTokens.colorGreen800),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Stale-while-revalidate (perf-review #1/#10): the chat SHELL (header + composer) is
              // already outside this Expanded, so render skeleton bubbles here on a first load —
              // and the LAST-KNOWN messages via `valueOrNull` on re-entry — instead of a blank
              // full-screen spinner while history loads and the socket connects.
              child: Builder(builder: (context) {
                final messages = async.valueOrNull;
                if (messages == null) {
                  if (async.hasError) {
                    return PgErrorState(
                      title: isThai
                          ? 'โหลดข้อความไม่สำเร็จ'
                          : 'Could not load messages',
                      message: async.error is ApiException
                          ? (async.error as ApiException).message
                          : null,
                      onRetry: () => ref.invalidate(provider),
                    );
                  }
                  return const _ChatSkeleton();
                }
                return messages.isEmpty
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
                            counterpartName: counterpartLabel,
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
                      );
              }),
            ),
            if (effectiveReadOnly)
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
/// First-load skeleton for the message area (perf-review #10): a few placeholder bubbles alternating
/// sides so the thread shows its shape while history loads + the socket connects, instead of blanking.
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
          vertical: PgTokens.space3, horizontal: PgTokens.space4),
      children: const [
        _SkeletonBubble(alignEnd: false, width: 160),
        SizedBox(height: PgTokens.space3),
        _SkeletonBubble(alignEnd: true, width: 120),
        SizedBox(height: PgTokens.space3),
        _SkeletonBubble(alignEnd: false, width: 200),
        SizedBox(height: PgTokens.space3),
        _SkeletonBubble(alignEnd: true, width: 90),
      ],
    );
  }
}

class _SkeletonBubble extends StatelessWidget {
  const _SkeletonBubble({required this.alignEnd, required this.width});

  final bool alignEnd;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: PgSkeletonBox(width: width, height: 34, radius: PgTokens.radiusXl),
    );
  }
}

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

/// The in-thread voice-call action (header trailing). Enabled only when the booking is callable
/// (guard accepted + job in flight); otherwise it stays visible but disabled with a tap-to-hint
/// snackbar so the user learns WHEN calling becomes available instead of hitting a 409 error.
class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.enabled,
    required this.isThai,
    required this.onCall,
  });

  final bool enabled;
  final bool isThai;
  final VoidCallback onCall;

  void _hint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isThai
          ? 'โทรได้หลังเจ้าหน้าที่รับงาน'
          : 'Available after a guard accepts'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        // Always tappable: disabled → explain why (don't route into a guaranteed error).
        onPressed: enabled ? onCall : () => _hint(context),
        tooltip: enabled
            ? (isThai ? 'โทร' : 'Call')
            : (isThai
                ? 'โทรได้หลังเจ้าหน้าที่รับงาน'
                : 'Available after a guard accepts'),
        icon: Icon(
          Icons.call_outlined,
          size: 22,
          color: enabled ? PgTokens.colorPrimary : PgTokens.colorTextFaint,
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
