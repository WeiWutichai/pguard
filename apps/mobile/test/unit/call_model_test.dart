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

  group('CallSummary (SERVER-emitted call-summary system message)', () {
    // The pinned shared contract: a `system` chat message whose content is this JSON, emitted by
    // the chat service from the `calling.ended` event. The mobile only parses + renders it.
    String summaryJson(String ct, String oc, Object? ds) =>
        '{"k":"call","ct":"$ct","oc":"$oc","ds":$ds}';

    test('tryParseContent: parses type + outcome + duration from the pinned JSON', () {
      final parsed =
          CallSummary.tryParseContent(summaryJson('audio', 'completed', 154));
      expect(parsed, isNotNull);
      expect(parsed!.type, CallType.audio);
      expect(parsed.outcome, CallOutcome.completed);
      expect(parsed.durationSeconds, 154);
    });

    test('tryParseContent: a null duration (never answered) → null ds', () {
      final parsed =
          CallSummary.tryParseContent(summaryJson('video', 'missed', null));
      expect(parsed!.type, CallType.video);
      expect(parsed.outcome, CallOutcome.missed);
      expect(parsed.durationSeconds, isNull);
    });

    test('tryParseContent: rejected outcome (the server can send it)', () {
      expect(CallSummary.tryParseContent(summaryJson('audio', 'rejected', null))!.outcome,
          CallOutcome.rejected);
    });

    test('tryParseContent: non-call / non-JSON / unknown → null (renders verbatim)', () {
      expect(CallSummary.tryParseContent('Booking confirmed'), isNull);
      expect(CallSummary.tryParseContent('{not json'), isNull);
      expect(CallSummary.tryParseContent('{"k":"other"}'), isNull);
      expect(
          CallSummary.tryParseContent('{"k":"call","ct":"audio","oc":"bogus"}'),
          isNull,
          reason: 'unknown outcome → render verbatim, never throw');
      expect(CallSummary.tryParseContent(null), isNull);
      expect(CallSummary.tryParseContent(''), isNull);
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

    test('line: rejected detail (TH + EN) — the server can send rejected', () {
      expect(
        CallSummary.line(
            type: CallType.audio, outcome: CallOutcome.rejected, thai: true),
        '📞 สายเสียง · ปฏิเสธสาย',
      );
      expect(
        CallSummary.line(
            type: CallType.audio, outcome: CallOutcome.rejected, thai: false),
        '📞 Voice call · Declined',
      );
    });

    test('round-trip: parse the pinned JSON then render the localized line', () {
      final parsed =
          CallSummary.tryParseContent(summaryJson('video', 'completed', 9))!;
      expect(
        CallSummary.line(
            type: parsed.type,
            outcome: parsed.outcome,
            thai: false,
            durationSeconds: parsed.durationSeconds),
        '📹 Video call · 0:09',
      );
    });
  });
}
