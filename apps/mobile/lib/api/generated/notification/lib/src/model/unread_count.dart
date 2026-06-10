//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unread_count.g.dart';

/// UnreadCount
///
/// Properties:
/// * [count] 
@BuiltValue()
abstract class UnreadCount implements Built<UnreadCount, UnreadCountBuilder> {
  @BuiltValueField(wireName: r'count')
  int get count;

  UnreadCount._();

  factory UnreadCount([void updates(UnreadCountBuilder b)]) = _$UnreadCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnreadCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnreadCount> get serializer => _$UnreadCountSerializer();
}

class _$UnreadCountSerializer implements PrimitiveSerializer<UnreadCount> {
  @override
  final Iterable<Type> types = const [UnreadCount, _$UnreadCount];

  @override
  final String wireName = r'UnreadCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnreadCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UnreadCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UnreadCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UnreadCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnreadCountBuilder();
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

