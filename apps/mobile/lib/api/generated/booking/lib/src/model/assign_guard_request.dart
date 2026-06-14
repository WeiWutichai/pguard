//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'assign_guard_request.g.dart';

/// AssignGuardRequest
///
/// Properties:
/// * [guardId] - The guard the admin assigns to this booking.
@BuiltValue()
abstract class AssignGuardRequest implements Built<AssignGuardRequest, AssignGuardRequestBuilder> {
  /// The guard the admin assigns to this booking.
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  AssignGuardRequest._();

  factory AssignGuardRequest([void updates(AssignGuardRequestBuilder b)]) = _$AssignGuardRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AssignGuardRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AssignGuardRequest> get serializer => _$AssignGuardRequestSerializer();
}

class _$AssignGuardRequestSerializer implements PrimitiveSerializer<AssignGuardRequest> {
  @override
  final Iterable<Type> types = const [AssignGuardRequest, _$AssignGuardRequest];

  @override
  final String wireName = r'AssignGuardRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AssignGuardRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AssignGuardRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AssignGuardRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AssignGuardRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AssignGuardRequestBuilder();
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

