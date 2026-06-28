//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify2fa_request.g.dart';

/// Second login step. Carries the single-use `challenge_token` from login plus EITHER a TOTP `code` OR a one-time `recovery_code`. 
///
/// Properties:
/// * [challengeToken] - The challenge token returned by login.
/// * [code] - A 6-digit TOTP code.
/// * [recoveryCode] - A one-time recovery code.
@BuiltValue()
abstract class Verify2faRequest implements Built<Verify2faRequest, Verify2faRequestBuilder> {
  /// The challenge token returned by login.
  @BuiltValueField(wireName: r'challenge_token')
  String get challengeToken;

  /// A 6-digit TOTP code.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// A one-time recovery code.
  @BuiltValueField(wireName: r'recovery_code')
  String? get recoveryCode;

  Verify2faRequest._();

  factory Verify2faRequest([void updates(Verify2faRequestBuilder b)]) = _$Verify2faRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Verify2faRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Verify2faRequest> get serializer => _$Verify2faRequestSerializer();
}

class _$Verify2faRequestSerializer implements PrimitiveSerializer<Verify2faRequest> {
  @override
  final Iterable<Type> types = const [Verify2faRequest, _$Verify2faRequest];

  @override
  final String wireName = r'Verify2faRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Verify2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'challenge_token';
    yield serializers.serialize(
      object.challengeToken,
      specifiedType: const FullType(String),
    );
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.recoveryCode != null) {
      yield r'recovery_code';
      yield serializers.serialize(
        object.recoveryCode,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Verify2faRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Verify2faRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'challenge_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.challengeToken = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'recovery_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.recoveryCode = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Verify2faRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Verify2faRequestBuilder();
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

