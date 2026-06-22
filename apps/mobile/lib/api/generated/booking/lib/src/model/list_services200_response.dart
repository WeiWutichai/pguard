//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/public_service_item.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_services200_response.g.dart';

/// ListServices200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListServices200Response implements ApiResponseEnvelope, Built<ListServices200Response, ListServices200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<PublicServiceItem>? get data;

  ListServices200Response._();

  factory ListServices200Response([void updates(ListServices200ResponseBuilder b)]) = _$ListServices200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListServices200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListServices200Response> get serializer => _$ListServices200ResponseSerializer();
}

class _$ListServices200ResponseSerializer implements PrimitiveSerializer<ListServices200Response> {
  @override
  final Iterable<Type> types = const [ListServices200Response, _$ListServices200Response];

  @override
  final String wireName = r'ListServices200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListServices200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(PublicServiceItem)]),
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
    ListServices200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListServices200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(PublicServiceItem)]),
          ) as BuiltList<PublicServiceItem>;
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
  ListServices200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListServices200ResponseBuilder();
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

