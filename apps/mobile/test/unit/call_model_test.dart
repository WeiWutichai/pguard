import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/call.dart';
import 'package:pguard_mobile/core/network/sockets/call_socket.dart';

void main() {
  group('CallSignal toJson / tryParse', () {
    test('offer / answer carry sdp; candidate carries the ICE fields; ready/bye are bare', () {
      final offer = CallSignal.offer('SDP_O');
      expect(offer.toJson(), {'kind': 'offer', 'sdp': 'SDP_O'});
      expect(CallSignal.tryParse(offer.toJson())!.sdp, 'SDP_O');

      final cand = CallSignal.candidate(
          candidate: 'cand', sdpMid: '0', sdpMLineIndex: 1);
      expect(cand.toJson(),
          {'kind': 'candidate', 'candidate': 'cand', 'sdpMid': '0', 'sdpMLineIndex': 1});
      final parsed = CallSignal.tryParse(cand.toJson())!;
      expect(parsed.candidate, 'cand');
      expect(parsed.sdpMLineIndex, 1);

      expect(CallSignal.ready().toJson(), {'kind': 'ready'});
      expect(CallSignal.bye().toJson(), {'kind': 'bye'});
    });

    test('tryParse rejects a payload with no/unknown kind', () {
      expect(CallSignal.tryParse({'sdp': 'x'}), isNull);
      expect(CallSignal.tryParse({'kind': 'nope'}), isNull);
      expect(CallSignal.tryParse('not a map'), isNull);
    });
  });

  group('CallSignalFrame.tryParse', () {
    test('parses a relay signal frame', () {
      final f = CallSignalFrame.tryParse({
        'type': 'signal',
        'from': 'peer',
        'call_id': 'c1',
        'signal': {'kind': 'answer', 'sdp': 'A'},
      });
      expect(f, isNotNull);
      expect(f!.callId, 'c1');
      expect(f.from, 'peer');
      expect(f.signal.kind, CallSignalKind.answer);
      expect(f.signal.sdp, 'A');
    });

    test('returns null for an error frame / a frame with no call_id / bad signal', () {
      expect(
          CallSignalFrame.tryParse({'type': 'error', 'message': 'x'}), isNull);
      expect(
          CallSignalFrame.tryParse(
              {'type': 'signal', 'signal': {'kind': 'bye'}}),
          isNull);
      expect(
          CallSignalFrame.tryParse(
              {'type': 'signal', 'call_id': 'c1', 'signal': {'kind': 'huh'}}),
          isNull);
    });
  });

  group('Call / enums', () {
    test('Call.fromJson maps the contract fields', () {
      final call = Call.fromJson({
        'id': 'c1',
        'caller_id': 'a',
        'callee_id': 'b',
        'booking_id': 'bk',
        'call_type': 'video',
        'status': 'connected',
        'duration_seconds': 42,
      });
      expect(call.id, 'c1');
      expect(call.calleeId, 'b');
      expect(call.callType, CallType.video);
      expect(call.status, CallStatus.connected);
      expect(call.durationSeconds, 42);
    });

    test('CallType.parse + CallStatus terminal classification', () {
      expect(CallType.parse('video'), CallType.video);
      expect(CallType.parse(null), CallType.audio);
      expect(CallStatus.parse('ended').isTerminal, isTrue);
      expect(CallStatus.parse('rejected').isTerminal, isTrue);
      expect(CallStatus.parse('missed').isTerminal, isTrue);
      expect(CallStatus.parse('connected').isTerminal, isFalse);
    });
  });

  group('CallState', () {
    test('idle defaults + copyWith', () {
      expect(CallState.idle.phase, CallPhase.idle);
      expect(CallState.idle.isActive, isFalse);
      final dialing = CallState.idle
          .copyWith(phase: CallPhase.dialing, callType: CallType.video, isCaller: true);
      expect(dialing.isRinging, isTrue);
      expect(dialing.callType, CallType.video);
      expect(dialing.copyWith(phase: CallPhase.active).isActive, isTrue);
    });
  });

  group('CallSummary (chat-thread line)', () {
    test('outcomeFrom: connected → completed regardless of reason', () {
      expect(CallSummary.outcomeFrom(wentActive: true, endReason: 'hangup'),
          CallOutcome.completed);
      expect(CallSummary.outcomeFrom(wentActive: true, endReason: 'remote_hangup'),
          CallOutcome.completed);
    });

    test('outcomeFrom: never-connected maps reason → rejected/failed/missed', () {
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: 'rejected'),
          CallOutcome.rejected);
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: 'error'),
          CallOutcome.failed);
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: 'media_failed'),
          CallOutcome.failed);
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: 'no_answer'),
          CallOutcome.missed);
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: 'hangup'),
          CallOutcome.missed);
      expect(CallSummary.outcomeFrom(wentActive: false, endReason: null),
          CallOutcome.missed);
    });

    test('formatDuration: M:SS with zero-padded seconds; clamps negative/null', () {
      expect(CallSummary.formatDuration(154), '2:34');
      expect(CallSummary.formatDuration(9), '0:09');
      expect(CallSummary.formatDuration(60), '1:00');
      expect(CallSummary.formatDuration(0), '0:00');
      expect(CallSummary.formatDuration(null), '0:00');
      expect(CallSummary.formatDuration(-5), '0:00');
    });

    test('line: completed audio shows the duration (TH + EN)', () {
      expect(
        CallSummary.line(
            type: CallType.audio,
            outcome: CallOutcome.completed,
            thai: true,
            durationSeconds: 154),
        '📞 สายเสียง · 2:34',
      );
      expect(
        CallSummary.line(
            type: CallType.audio,
            outcome: CallOutcome.completed,
            thai: false,
            durationSeconds: 154),
        '📞 Voice call · 2:34',
      );
    });

    test('line: missed video uses the video emoji + outcome detail', () {
      expect(
        CallSummary.line(
            type: CallType.video, outcome: CallOutcome.missed, thai: true),
        '📹 วิดีโอคอล · ไม่ได้รับสาย',
      );
      expect(
        CallSummary.line(
            type: CallType.video, outcome: CallOutcome.missed, thai: false),
        '📹 Video call · Missed call',
      );
    });

    test('line: rejected + failed details', () {
      expect(
        CallSummary.line(
            type: CallType.audio, outcome: CallOutcome.rejected, thai: true),
        '📞 สายเสียง · ปฏิเสธสาย',
      );
      expect(
        CallSummary.line(
            type: CallType.audio, outcome: CallOutcome.failed, thai: false),
        '📞 Voice call · Call failed',
      );
    });
  });
}
