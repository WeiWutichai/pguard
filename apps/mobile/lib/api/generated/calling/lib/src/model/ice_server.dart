//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ice_server.g.dart';

/// One WebRTC ICE server (STUN = urls only; TURN = urls + short-lived username/credential).
///
/// Properties:
/// * [urls] - STUN/TURN URLs, e.g. \"stun:stun.l.google.com:19302\" or \"turn:turn.pguard.app:3478?transport=udp\".
/// * [username] - TURN only — \"<expiry_unix>:<user_id>\".
/// * [credential] - TURN only — base64(HMAC-SHA1(secret, username)); short-lived.
@BuiltValue()
abstract class IceServer implements Built<IceServer, IceServerBuilder> {
  /// STUN/TURN URLs, e.g. \"stun:stun.l.google.com:19302\" or \"turn:turn.pguard.app:3478?transport=udp\".
  @BuiltValueField(wireName: r'urls')
  BuiltList<String> get urls;

  /// TURN only — \"<expiry_unix>:<user_id>\".
  @BuiltValueField(wireName: r'username')
  String? get username;

  /// TURN only — base64(HMAC-SHA1(secret, username)); short-lived.
  @BuiltValueField(wireName: r'credential')
  String? get credential;

  IceServer._();

  factory IceServer([void updates(IceServerBuilder b)]) = _$IceServer;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(IceServerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<IceServer> get serializer => _$IceServerSerializer();
}

class _$IceServerSerializer implements PrimitiveSerializer<IceServer> {
  @override
  final Iterable<Type> types = const [IceServer, _$IceServer];

  @override
  final String wireName = r'IceServer';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    IceServer object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'urls';
    yield serializers.serialize(
      object.urls,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.username != null) {
      yield r'username';
      yield serializers.serialize(
        object.username,
        specifiedType: const FullType(String),
      );
    }
    if (object.credential != null) {
      yield r'credential';
      yield serializers.serialize(
        object.credential,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    IceServer object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required IceServerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'urls':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.urls.replace(valueDes);
          break;
        case r'username':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.username = valueDes;
          break;
        case r'credential':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.credential = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  IceServer deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = IceServerBuilder();
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

