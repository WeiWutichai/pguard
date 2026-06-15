//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'stage_request.g.dart';

/// StageRequest
///
/// Properties:
/// * [stage] 
@BuiltValue()
abstract class StageRequest implements Built<StageRequest, StageRequestBuilder> {
  @BuiltValueField(wireName: r'stage')
  StageRequestStageEnum get stage;
  // enum stageEnum {  sourcing,  screened,  docs_verified,  };

  StageRequest._();

  factory StageRequest([void updates(StageRequestBuilder b)]) = _$StageRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StageRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StageRequest> get serializer => _$StageRequestSerializer();
}

class _$StageRequestSerializer implements PrimitiveSerializer<StageRequest> {
  @override
  final Iterable<Type> types = const [StageRequest, _$StageRequest];

  @override
  final String wireName = r'StageRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StageRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'stage';
    yield serializers.serialize(
      object.stage,
      specifiedType: const FullType(StageRequestStageEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    StageRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StageRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'stage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(StageRequestStageEnum),
          ) as StageRequestStageEnum;
          result.stage = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StageRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StageRequestBuilder();
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

class StageRequestStageEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'sourcing')
  static const StageRequestStageEnum sourcing = _$stageRequestStageEnum_sourcing;
  @BuiltValueEnumConst(wireName: r'screened')
  static const StageRequestStageEnum screened = _$stageRequestStageEnum_screened;
  @BuiltValueEnumConst(wireName: r'docs_verified')
  static const StageRequestStageEnum docsVerified = _$stageRequestStageEnum_docsVerified;

  static Serializer<StageRequestStageEnum> get serializer => _$stageRequestStageEnumSerializer;

  const StageRequestStageEnum._(String name): super(name);

  static BuiltSet<StageRequestStageEnum> get values => _$stageRequestStageEnumValues;
  static StageRequestStageEnum valueOf(String name) => _$stageRequestStageEnumValueOf(name);
}

