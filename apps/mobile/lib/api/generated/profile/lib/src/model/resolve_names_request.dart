//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'resolve_names_request.g.dart';

/// A batch of user_ids to resolve to display names (admin lists). Duplicates are de-duplicated server-side; an empty list returns an empty map. Bounded to 500 ids per call (a larger batch → 400 — page the calls). 
///
/// Properties:
/// * [ids] - The user_ids to resolve.
@BuiltValue()
abstract class ResolveNamesRequest implements Built<ResolveNamesRequest, ResolveNamesRequestBuilder> {
  /// The user_ids to resolve.
  @BuiltValueField(wireName: r'ids')
  BuiltList<String> get ids;

  ResolveNamesRequest._();

  factory ResolveNamesRequest([void updates(ResolveNamesRequestBuilder b)]) = _$ResolveNamesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResolveNamesRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResolveNamesRequest> get serializer => _$ResolveNamesRequestSerializer();
}

class _$ResolveNamesRequestSerializer implements PrimitiveSerializer<ResolveNamesRequest> {
  @override
  final Iterable<Type> types = const [ResolveNamesRequest, _$ResolveNamesRequest];

  @override
  final String wireName = r'ResolveNamesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResolveNamesRequest object, {
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
    ResolveNamesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResolveNamesRequestBuilder result,
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
  ResolveNamesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResolveNamesRequestBuilder();
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

