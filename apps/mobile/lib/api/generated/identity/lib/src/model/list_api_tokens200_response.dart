//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/api_token_view.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_api_tokens200_response.g.dart';

/// ListApiTokens200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListApiTokens200Response implements ApiResponseEnvelope, Built<ListApiTokens200Response, ListApiTokens200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<ApiTokenView>? get data;

  ListApiTokens200Response._();

  factory ListApiTokens200Response([void updates(ListApiTokens200ResponseBuilder b)]) = _$ListApiTokens200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListApiTokens200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListApiTokens200Response> get serializer => _$ListApiTokens200ResponseSerializer();
}

class _$ListApiTokens200ResponseSerializer implements PrimitiveSerializer<ListApiTokens200Response> {
  @override
  final Iterable<Type> types = const [ListApiTokens200Response, _$ListApiTokens200Response];

  @override
  final String wireName = r'ListApiTokens200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListApiTokens200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(ApiTokenView)]),
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
    ListApiTokens200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListApiTokens200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ApiTokenView)]),
          ) as BuiltList<ApiTokenView>;
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
  ListApiTokens200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListApiTokens200ResponseBuilder();
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

