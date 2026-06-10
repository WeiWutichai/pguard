//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_result.g.dart';

/// RegisterResult
///
/// Properties:
/// * [userId] 
/// * [profileToken] - Single-use, purpose-scoped JWT (`guard_profile` / `customer_profile`) the client exchanges at `POST /profile/{guard,customer}`. NOT an access token. 
@BuiltValue()
abstract class RegisterResult implements Built<RegisterResult, RegisterResultBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  /// Single-use, purpose-scoped JWT (`guard_profile` / `customer_profile`) the client exchanges at `POST /profile/{guard,customer}`. NOT an access token. 
  @BuiltValueField(wireName: r'profile_token')
  String get profileToken;

  RegisterResult._();

  factory RegisterResult([void updates(RegisterResultBuilder b)]) = _$RegisterResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegisterResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegisterResult> get serializer => _$RegisterResultSerializer();
}

class _$RegisterResultSerializer implements PrimitiveSerializer<RegisterResult> {
  @override
  final Iterable<Type> types = const [RegisterResult, _$RegisterResult];

  @override
  final String wireName = r'RegisterResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegisterResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    yield r'profile_token';
    yield serializers.serialize(
      object.profileToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RegisterResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RegisterResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'profile_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.profileToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegisterResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegisterResultBuilder();
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

