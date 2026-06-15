//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_notification_api/src/model/broadcast.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_broadcasts200_response.g.dart';

/// ListBroadcasts200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListBroadcasts200Response implements ApiResponseEnvelope, Built<ListBroadcasts200Response, ListBroadcasts200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<Broadcast>? get data;

  ListBroadcasts200Response._();

  factory ListBroadcasts200Response([void updates(ListBroadcasts200ResponseBuilder b)]) = _$ListBroadcasts200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListBroadcasts200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListBroadcasts200Response> get serializer => _$ListBroadcasts200ResponseSerializer();
}

class _$ListBroadcasts200ResponseSerializer implements PrimitiveSerializer<ListBroadcasts200Response> {
  @override
  final Iterable<Type> types = const [ListBroadcasts200Response, _$ListBroadcasts200Response];

  @override
  final String wireName = r'ListBroadcasts200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListBroadcasts200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(Broadcast)]),
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
    ListBroadcasts200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListBroadcasts200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Broadcast)]),
          ) as BuiltList<Broadcast>;
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
  ListBroadcasts200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListBroadcasts200ResponseBuilder();
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

