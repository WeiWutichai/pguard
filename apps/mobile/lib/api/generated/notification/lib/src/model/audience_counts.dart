//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audience_counts.g.dart';

/// AudienceCounts
///
/// Properties:
/// * [all] 
/// * [guards] 
/// * [customers] 
@BuiltValue()
abstract class AudienceCounts implements Built<AudienceCounts, AudienceCountsBuilder> {
  @BuiltValueField(wireName: r'all')
  int get all;

  @BuiltValueField(wireName: r'guards')
  int get guards;

  @BuiltValueField(wireName: r'customers')
  int get customers;

  AudienceCounts._();

  factory AudienceCounts([void updates(AudienceCountsBuilder b)]) = _$AudienceCounts;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AudienceCountsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AudienceCounts> get serializer => _$AudienceCountsSerializer();
}

class _$AudienceCountsSerializer implements PrimitiveSerializer<AudienceCounts> {
  @override
  final Iterable<Type> types = const [AudienceCounts, _$AudienceCounts];

  @override
  final String wireName = r'AudienceCounts';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AudienceCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'all';
    yield serializers.serialize(
      object.all,
      specifiedType: const FullType(int),
    );
    yield r'guards';
    yield serializers.serialize(
      object.guards,
      specifiedType: const FullType(int),
    );
    yield r'customers';
    yield serializers.serialize(
      object.customers,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AudienceCounts object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AudienceCountsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'all':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.all = valueDes;
          break;
        case r'guards':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.guards = valueDes;
          break;
        case r'customers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.customers = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AudienceCounts deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AudienceCountsBuilder();
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

