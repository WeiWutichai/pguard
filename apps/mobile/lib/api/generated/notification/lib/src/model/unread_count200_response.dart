//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:pguard_notification_api/src/model/unread_count.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unread_count200_response.g.dart';

/// UnreadCount200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class UnreadCount200Response implements ApiResponseEnvelope, Built<UnreadCount200Response, UnreadCount200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  UnreadCount? get data;

  UnreadCount200Response._();

  factory UnreadCount200Response([void updates(UnreadCount200ResponseBuilder b)]) = _$UnreadCount200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnreadCount200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnreadCount200Response> get serializer => _$UnreadCount200ResponseSerializer();
}

class _$UnreadCount200ResponseSerializer implements PrimitiveSerializer<UnreadCount200Response> {
  @override
  final Iterable<Type> types = const [UnreadCount200Response, _$UnreadCount200Response];

  @override
  final String wireName = r'UnreadCount200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnreadCount200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(UnreadCount),
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
    UnreadCount200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UnreadCount200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(UnreadCount),
          ) as UnreadCount;
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
  UnreadCount200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnreadCount200ResponseBuilder();
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

