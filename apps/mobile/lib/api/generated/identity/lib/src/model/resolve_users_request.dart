//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolve_users_request.g.dart';

/// Batch of user_ids to resolve to `{ role, display_name, phone }`. Duplicates are de-duplicated server-side; an empty list → an empty map. Bounded to 500 ids (a larger batch → 400). 
///
/// Properties:
/// * [ids] 
@BuiltValue()
abstract class ResolveUsersRequest implements Built<ResolveUsersRequest, ResolveUsersRequestBuilder> {
  @BuiltValueField(wireName: r'ids')
  BuiltList<String> get ids;

  ResolveUsersRequest._();

  factory ResolveUsersRequest([void updates(ResolveUsersRequestBuilder b)]) = _$ResolveUsersRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResolveUsersRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResolveUsersRequest> get serializer => _$ResolveUsersRequestSerializer();
}

class _$ResolveUsersRequestSerializer implements PrimitiveSerializer<ResolveUsersRequest> {
  @override
  final Iterable<Type> types = const [ResolveUsersRequest, _$ResolveUsersRequest];

  @override
  final String wireName = r'ResolveUsersRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResolveUsersRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'ids';
    yield serializers.serialize(
      object.ids,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ResolveUsersRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResolveUsersRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.ids.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResolveUsersRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResolveUsersRequestBuilder();
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

