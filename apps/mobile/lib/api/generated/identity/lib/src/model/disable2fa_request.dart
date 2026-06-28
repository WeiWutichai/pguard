//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'disable2fa_request.g.dart';

/// Confirm intent with EITHER a live TOTP `code` OR the account `password` (at least one). 
///
/// Properties:
/// * [code] - A live 6-digit TOTP code.
/// * [password] - SHA-256 hex of the account PIN (same shape as login's `password`).
@BuiltValue()
abstract class Disable2faRequest implements Built<Disable2faRequest, Disable2faRequestBuilder> {
  /// A live 6-digit TOTP code.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// SHA-256 hex of the account PIN (same shape as login's `password`).
  @BuiltValueField(wireName: r'password')
  String? get password;

  Disable2faRequest._();

  factory Disable2faRequest([void updates(Disable2faRequestBuilder b)]) = _$Disable2faRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Disable2faRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Disable2faRequest> get serializer => _$Disable2faRequestSerializer();
}

class _$Disable2faRequestSerializer implements PrimitiveSerializer<Disable2faRequest> {
  @override
  final Iterable<Type> types = const [Disable2faRequest, _$Disable2faRequest];

  @override
  final String wireName = r'Disable2faRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Disable2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.password != null) {
      yield r'password';
      yield serializers.serialize(
        object.password,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Disable2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Disable2faRequestBuilder result,
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
        case r'password':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.password = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Disable2faRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Disable2faRequestBuilder();
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

