//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'request_otp_result.g.dart';

/// RequestOtpResult
///
/// Properties:
/// * [message] 
/// * [expiresIn] - OTP validity in seconds
@BuiltValue()
abstract class RequestOtpResult implements Built<RequestOtpResult, RequestOtpResultBuilder> {
  @BuiltValueField(wireName: r'message')
  String get message;

  /// OTP validity in seconds
  @BuiltValueField(wireName: r'expires_in')
  int get expiresIn;

  RequestOtpResult._();

  factory RequestOtpResult([void updates(RequestOtpResultBuilder b)]) = _$RequestOtpResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RequestOtpResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RequestOtpResult> get serializer => _$RequestOtpResultSerializer();
}

class _$RequestOtpResultSerializer implements PrimitiveSerializer<RequestOtpResult> {
  @override
  final Iterable<Type> types = const [RequestOtpResult, _$RequestOtpResult];

  @override
  final String wireName = r'RequestOtpResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RequestOtpResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
    yield r'expires_in';
    yield serializers.serialize(
      object.expiresIn,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RequestOtpResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RequestOtpResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'expires_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expiresIn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RequestOtpResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RequestOtpResultBuilder();
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

