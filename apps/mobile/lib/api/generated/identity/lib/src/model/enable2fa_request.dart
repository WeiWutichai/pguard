//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enable2fa_request.g.dart';

/// Enable2faRequest
///
/// Properties:
/// * [code] - The 6-digit TOTP code from the authenticator app.
@BuiltValue()
abstract class Enable2faRequest implements Built<Enable2faRequest, Enable2faRequestBuilder> {
  /// The 6-digit TOTP code from the authenticator app.
  @BuiltValueField(wireName: r'code')
  String get code;

  Enable2faRequest._();

  factory Enable2faRequest([void updates(Enable2faRequestBuilder b)]) = _$Enable2faRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Enable2faRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Enable2faRequest> get serializer => _$Enable2faRequestSerializer();
}

class _$Enable2faRequestSerializer implements PrimitiveSerializer<Enable2faRequest> {
  @override
  final Iterable<Type> types = const [Enable2faRequest, _$Enable2faRequest];

  @override
  final String wireName = r'Enable2faRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Enable2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Enable2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Enable2faRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  Enable2faRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Enable2faRequestBuilder();
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

