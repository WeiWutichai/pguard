//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'progress_report.g.dart';

/// One hourly check-in. `photo_url` is a FRESH presigned GET URL (TTL 1h) signed per read from the stored `photo_key` — the bucket and credentials are never exposed. 
///
/// Properties:
/// * [id] 
/// * [bookingId] 
/// * [guardId] 
/// * [hourNumber] 
/// * [photoKey] - S3 object key (internal reference; not directly fetchable).
/// * [photoUrl] - Fresh presigned download URL (TTL 1h).
/// * [lat] 
/// * [lng] 
/// * [accuracyM] 
/// * [note] 
/// * [createdAt] 
@BuiltValue()
abstract class ProgressReport implements Built<ProgressReport, ProgressReportBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'hour_number')
  int get hourNumber;

  /// S3 object key (internal reference; not directly fetchable).
  @BuiltValueField(wireName: r'photo_key')
  String get photoKey;

  /// Fresh presigned download URL (TTL 1h).
  @BuiltValueField(wireName: r'photo_url')
  String get photoUrl;

  @BuiltValueField(wireName: r'lat')
  double? get lat;

  @BuiltValueField(wireName: r'lng')
  double? get lng;

  @BuiltValueField(wireName: r'accuracy_m')
  double? get accuracyM;

  @BuiltValueField(wireName: r'note')
  String? get note;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  ProgressReport._();

  factory ProgressReport([void updates(ProgressReportBuilder b)]) = _$ProgressReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ProgressReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ProgressReport> get serializer => _$ProgressReportSerializer();
}

class _$ProgressReportSerializer implements PrimitiveSerializer<ProgressReport> {
  @override
  final Iterable<Type> types = const [ProgressReport, _$ProgressReport];

  @override
  final String wireName = r'ProgressReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ProgressReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'hour_number';
    yield serializers.serialize(
      object.hourNumber,
      specifiedType: const FullType(int),
    );
    yield r'photo_key';
    yield serializers.serialize(
      object.photoKey,
      specifiedType: const FullType(String),
    );
    yield r'photo_url';
    yield serializers.serialize(
      object.photoUrl,
      specifiedType: const FullType(String),
    );
    if (object.lat != null) {
      yield r'lat';
      yield serializers.serialize(
        object.lat,
        specifiedType: const FullType(double),
      );
    }
    if (object.lng != null) {
      yield r'lng';
      yield serializers.serialize(
        object.lng,
        specifiedType: const FullType(double),
      );
    }
    if (object.accuracyM != null) {
      yield r'accuracy_m';
      yield serializers.serialize(
        object.accuracyM,
        specifiedType: const FullType(double),
      );
    }
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ProgressReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ProgressReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'hour_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.hourNumber = valueDes;
          break;
        case r'photo_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.photoKey = valueDes;
          break;
        case r'photo_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.photoUrl = valueDes;
          break;
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lat = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lng = valueDes;
          break;
        case r'accuracy_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.accuracyM = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ProgressReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ProgressReportBuilder();
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

