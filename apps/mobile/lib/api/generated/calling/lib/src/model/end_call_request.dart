//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'end_call_request.g.dart';

/// EndCallRequest
///
/// Properties:
/// * [reason] - Optional audit reason (e.g. \"hangup\").
@BuiltValue()
abstract class EndCallRequest implements Built<EndCallRequest, EndCallRequestBuilder> {
  /// Optional audit reason (e.g. \"hangup\").
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  EndCallRequest._();

  factory EndCallRequest([void updates(EndCallRequestBuilder b)]) = _$EndCallRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EndCallRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EndCallRequest> get serializer => _$EndCallRequestSerializer();
}

class _$EndCallRequestSerializer implements PrimitiveSerializer<EndCallRequest> {
  @override
  final Iterable<Type> types = const [EndCallRequest, _$EndCallRequest];

  @override
  final String wireName = r'EndCallRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EndCallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EndCallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EndCallRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EndCallRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EndCallRequestBuilder();
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

