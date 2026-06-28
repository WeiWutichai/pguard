//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_presence_api/src/model/history_point.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'track_replay.g.dart';

/// TrackReplay
///
/// Properties:
/// * [guardId] - The guard whose track this is (resolved from the booking in by-JOB mode).
/// * [bookingId] - Present only in by-JOB mode — the booking the window was derived from.
/// * [from] - Window start (inclusive).
/// * [to] - Window end (exclusive).
/// * [windowOpen] - by-JOB only — true when the job is still active (no terminal event yet), so `to` was clamped to the request time. Always false in by-GUARD mode. 
/// * [points] - The GPS track, OLDEST-first. Each point carries its `recorded_at`.
/// * [limit] - The applied point cap (default 500, hard max 1000).
/// * [truncated] - True when the window holds at least `limit` points (page/narrow to see more).
/// * [perPointSpeedHeadingAvailable] - Always false — `location_history` does not store per-point speed/heading (live-only signals, never historized). A FLAG, not a fabrication. 
@BuiltValue()
abstract class TrackReplay implements Built<TrackReplay, TrackReplayBuilder> {
  /// The guard whose track this is (resolved from the booking in by-JOB mode).
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// Present only in by-JOB mode — the booking the window was derived from.
  @BuiltValueField(wireName: r'booking_id')
  String? get bookingId;

  /// Window start (inclusive).
  @BuiltValueField(wireName: r'from')
  DateTime get from;

  /// Window end (exclusive).
  @BuiltValueField(wireName: r'to')
  DateTime get to;

  /// by-JOB only — true when the job is still active (no terminal event yet), so `to` was clamped to the request time. Always false in by-GUARD mode. 
  @BuiltValueField(wireName: r'window_open')
  bool get windowOpen;

  /// The GPS track, OLDEST-first. Each point carries its `recorded_at`.
  @BuiltValueField(wireName: r'points')
  BuiltList<HistoryPoint> get points;

  /// The applied point cap (default 500, hard max 1000).
  @BuiltValueField(wireName: r'limit')
  int get limit;

  /// True when the window holds at least `limit` points (page/narrow to see more).
  @BuiltValueField(wireName: r'truncated')
  bool get truncated;

  /// Always false — `location_history` does not store per-point speed/heading (live-only signals, never historized). A FLAG, not a fabrication. 
  @BuiltValueField(wireName: r'per_point_speed_heading_available')
  bool get perPointSpeedHeadingAvailable;

  TrackReplay._();

  factory TrackReplay([void updates(TrackReplayBuilder b)]) = _$TrackReplay;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TrackReplayBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TrackReplay> get serializer => _$TrackReplaySerializer();
}

class _$TrackReplaySerializer implements PrimitiveSerializer<TrackReplay> {
  @override
  final Iterable<Type> types = const [TrackReplay, _$TrackReplay];

  @override
  final String wireName = r'TrackReplay';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TrackReplay object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.bookingId != null) {
      yield r'booking_id';
      yield serializers.serialize(
        object.bookingId,
        specifiedType: const FullType(String),
      );
    }
    yield r'from';
    yield serializers.serialize(
      object.from,
      specifiedType: const FullType(DateTime),
    );
    yield r'to';
    yield serializers.serialize(
      object.to,
      specifiedType: const FullType(DateTime),
    );
    yield r'window_open';
    yield serializers.serialize(
      object.windowOpen,
      specifiedType: const FullType(bool),
    );
    yield r'points';
    yield serializers.serialize(
      object.points,
      specifiedType: const FullType(BuiltList, [FullType(HistoryPoint)]),
    );
    yield r'limit';
    yield serializers.serialize(
      object.limit,
      specifiedType: const FullType(int),
    );
    yield r'truncated';
    yield serializers.serialize(
      object.truncated,
      specifiedType: const FullType(bool),
    );
    yield r'per_point_speed_heading_available';
    yield serializers.serialize(
      object.perPointSpeedHeadingAvailable,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    TrackReplay object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TrackReplayBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.from = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.to = valueDes;
          break;
        case r'window_open':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.windowOpen = valueDes;
          break;
        case r'points':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(HistoryPoint)]),
          ) as BuiltList<HistoryPoint>;
          result.points.replace(valueDes);
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        case r'truncated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.truncated = valueDes;
          break;
        case r'per_point_speed_heading_available':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.perPointSpeedHeadingAvailable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TrackReplay deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TrackReplayBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

