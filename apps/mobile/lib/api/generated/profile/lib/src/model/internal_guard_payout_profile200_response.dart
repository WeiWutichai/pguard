//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/guard_payout_profile.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_guard_payout_profile200_response.g.dart';

/// InternalGuardPayoutProfile200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class InternalGuardPayoutProfile200Response implements ApiResponseEnvelope, Built<InternalGuardPayoutProfile200Response, InternalGuardPayoutProfile200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  GuardPayoutProfile? get data;

  InternalGuardPayoutProfile200Response._();

  factory InternalGuardPayoutProfile200Response([void updates(InternalGuardPayoutProfile200ResponseBuilder b)]) = _$InternalGuardPayoutProfile200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalGuardPayoutProfile200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalGuardPayoutProfile200Response> get serializer => _$InternalGuardPayoutProfile200ResponseSerializer();
}

class _$InternalGuardPayoutProfile200ResponseSerializer implements PrimitiveSerializer<InternalGuardPayoutProfile200Response> {
  @override
  final Iterable<Type> types = const [InternalGuardPayoutProfile200Response, _$InternalGuardPayoutProfile200Response];

  @override
  final String wireName = r'InternalGuardPayoutProfile200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalGuardPayoutProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(GuardPayoutProfile),
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
    InternalGuardPayoutProfile200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalGuardPayoutProfile200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardPayoutProfile),
          ) as GuardPayoutProfile;
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
  InternalGuardPayoutProfile200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalGuardPayoutProfile200ResponseBuilder();
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

