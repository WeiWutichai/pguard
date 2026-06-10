//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_otp_request.g.dart';

/// VerifyOtpRequest
///
/// Properties:
/// * [phone] 
/// * [code] - The OTP code (digits)
@BuiltValue()
abstract class VerifyOtpRequest implements Built<VerifyOtpRequest, VerifyOtpRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  /// The OTP code (digits)
  @BuiltValueField(wireName: r'code')
  String get code;

  VerifyOtpRequest._();

  factory VerifyOtpRequest([void updates(VerifyOtpRequestBuilder b)]) = _$VerifyOtpRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyOtpRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyOtpRequest> get serializer => _$VerifyOtpRequestSerializer();
}

class _$VerifyOtpRequestSerializer implements PrimitiveSerializer<VerifyOtpRequest> {
  @override
  final Iterable<Type> types = const [VerifyOtpRequest, _$VerifyOtpRequest];

  @override
  final String wireName = r'VerifyOtpRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VerifyOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VerifyOtpRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VerifyOtpRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyOtpRequestBuilder();
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

