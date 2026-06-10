//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/available_guard.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_available_guards200_response.g.dart';

/// ListAvailableGuards200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListAvailableGuards200Response implements ApiResponseEnvelope, Built<ListAvailableGuards200Response, ListAvailableGuards200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<AvailableGuard>? get data;

  ListAvailableGuards200Response._();

  factory ListAvailableGuards200Response([void updates(ListAvailableGuards200ResponseBuilder b)]) = _$ListAvailableGuards200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListAvailableGuards200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListAvailableGuards200Response> get serializer => _$ListAvailableGuards200ResponseSerializer();
}

class _$ListAvailableGuards200ResponseSerializer implements PrimitiveSerializer<ListAvailableGuards200Response> {
  @override
  final Iterable<Type> types = const [ListAvailableGuards200Response, _$ListAvailableGuards200Response];

  @override
  final String wireName = r'ListAvailableGuards200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListAvailableGuards200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(AvailableGuard)]),
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
    ListAvailableGuards200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListAvailableGuards200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AvailableGuard)]),
          ) as BuiltList<AvailableGuard>;
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
  ListAvailableGuards200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListAvailableGuards200ResponseBuilder();
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

