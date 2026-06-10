//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_calling_api/src/model/ice_server.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ice_config.g.dart';

/// IceConfig
///
/// Properties:
/// * [iceServers] 
/// * [ttlSecs] - TURN credential lifetime; refetch before this elapses.
@BuiltValue()
abstract class IceConfig implements Built<IceConfig, IceConfigBuilder> {
  @BuiltValueField(wireName: r'ice_servers')
  BuiltList<IceServer> get iceServers;

  /// TURN credential lifetime; refetch before this elapses.
  @BuiltValueField(wireName: r'ttl_secs')
  int get ttlSecs;

  IceConfig._();

  factory IceConfig([void updates(IceConfigBuilder b)]) = _$IceConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(IceConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<IceConfig> get serializer => _$IceConfigSerializer();
}

class _$IceConfigSerializer implements PrimitiveSerializer<IceConfig> {
  @override
  final Iterable<Type> types = const [IceConfig, _$IceConfig];

  @override
  final String wireName = r'IceConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    IceConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'ice_servers';
    yield serializers.serialize(
      object.iceServers,
      specifiedType: const FullType(BuiltList, [FullType(IceServer)]),
    );
    yield r'ttl_secs';
    yield serializers.serialize(
      object.ttlSecs,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    IceConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required IceConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'ice_servers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(IceServer)]),
          ) as BuiltList<IceServer>;
          result.iceServers.replace(valueDes);
          break;
        case r'ttl_secs':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ttlSecs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  IceConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = IceConfigBuilder();
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

