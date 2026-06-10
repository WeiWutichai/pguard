//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'available_guard.g.dart';

/// An approved guard (profile catalog) enriched with their rating summary (rating).
///
/// Properties:
/// * [guardId] 
/// * [yearsOfExperience] 
/// * [averageRating] - AVG of visible overall ratings (decimal string); null if none / rating unreachable.
/// * [reviewCount] 
@BuiltValue()
abstract class AvailableGuard implements Built<AvailableGuard, AvailableGuardBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  /// AVG of visible overall ratings (decimal string); null if none / rating unreachable.
  @BuiltValueField(wireName: r'average_rating')
  String? get averageRating;

  @BuiltValueField(wireName: r'review_count')
  int get reviewCount;

  AvailableGuard._();

  factory AvailableGuard([void updates(AvailableGuardBuilder b)]) = _$AvailableGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvailableGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvailableGuard> get serializer => _$AvailableGuardSerializer();
}

class _$AvailableGuardSerializer implements PrimitiveSerializer<AvailableGuard> {
  @override
  final Iterable<Type> types = const [AvailableGuard, _$AvailableGuard];

  @override
  final String wireName = r'AvailableGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvailableGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
    if (object.averageRating != null) {
      yield r'average_rating';
      yield serializers.serialize(
        object.averageRating,
        specifiedType: const FullType(String),
      );
    }
    yield r'review_count';
    yield serializers.serialize(
      object.reviewCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AvailableGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AvailableGuardBuilder result,
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
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'average_rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.averageRating = valueDes;
          break;
        case r'review_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvailableGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvailableGuardBuilder();
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

