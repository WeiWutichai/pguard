//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_guard.g.dart';

/// The lean approved-guard row for internal discovery — deliberately NARROW (no bank/PII; least-privilege over the service-to-service wire). 
///
/// Properties:
/// * [userId] 
/// * [yearsOfExperience] 
@BuiltValue()
abstract class InternalGuard implements Built<InternalGuard, InternalGuardBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  InternalGuard._();

  factory InternalGuard([void updates(InternalGuardBuilder b)]) = _$InternalGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalGuard> get serializer => _$InternalGuardSerializer();
}

class _$InternalGuardSerializer implements PrimitiveSerializer<InternalGuard> {
  @override
  final Iterable<Type> types = const [InternalGuard, _$InternalGuard];

  @override
  final String wireName = r'InternalGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InternalGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalGuardBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InternalGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalGuardBuilder();
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

