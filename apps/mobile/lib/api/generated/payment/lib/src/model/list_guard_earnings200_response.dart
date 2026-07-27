//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/guard_earning.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_guard_earnings200_response.g.dart';

/// ListGuardEarnings200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListGuardEarnings200Response implements ApiResponseEnvelope, Built<ListGuardEarnings200Response, ListGuardEarnings200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<GuardEarning>? get data;

  ListGuardEarnings200Response._();

  factory ListGuardEarnings200Response([void updates(ListGuardEarnings200ResponseBuilder b)]) = _$ListGuardEarnings200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListGuardEarnings200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListGuardEarnings200Response> get serializer => _$ListGuardEarnings200ResponseSerializer();
}

class _$ListGuardEarnings200ResponseSerializer implements PrimitiveSerializer<ListGuardEarnings200Response> {
  @override
  final Iterable<Type> types = const [ListGuardEarnings200Response, _$ListGuardEarnings200Response];

  @override
  final String wireName = r'ListGuardEarnings200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListGuardEarnings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(GuardEarning)]),
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
    ListGuardEarnings200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListGuardEarnings200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(GuardEarning)]),
          ) as BuiltList<GuardEarning>;
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
  ListGuardEarnings200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListGuardEarnings200ResponseBuilder();
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

