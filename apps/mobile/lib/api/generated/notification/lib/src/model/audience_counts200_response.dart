//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:pguard_notification_api/src/model/audience_counts.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'audience_counts200_response.g.dart';

/// AudienceCounts200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AudienceCounts200Response implements ApiResponseEnvelope, Built<AudienceCounts200Response, AudienceCounts200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  AudienceCounts? get data;

  AudienceCounts200Response._();

  factory AudienceCounts200Response([void updates(AudienceCounts200ResponseBuilder b)]) = _$AudienceCounts200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AudienceCounts200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AudienceCounts200Response> get serializer => _$AudienceCounts200ResponseSerializer();
}

class _$AudienceCounts200ResponseSerializer implements PrimitiveSerializer<AudienceCounts200Response> {
  @override
  final Iterable<Type> types = const [AudienceCounts200Response, _$AudienceCounts200Response];

  @override
  final String wireName = r'AudienceCounts200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AudienceCounts200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(AudienceCounts),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AudienceCounts200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AudienceCounts200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AudienceCounts),
          ) as AudienceCounts;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AudienceCounts200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AudienceCounts200ResponseBuilder();
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

