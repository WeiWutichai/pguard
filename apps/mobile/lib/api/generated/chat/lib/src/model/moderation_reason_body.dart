//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'moderation_reason_body.g.dart';

/// Optional body shared by redact / block / unblock — an audited reason. The whole body may be omitted (the endpoints accept no body too).
///
/// Properties:
/// * [reason] - Optional audited reason recorded in `chat.moderation_actions`.
@BuiltValue()
abstract class ModerationReasonBody implements Built<ModerationReasonBody, ModerationReasonBodyBuilder> {
  /// Optional audited reason recorded in `chat.moderation_actions`.
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  ModerationReasonBody._();

  factory ModerationReasonBody([void updates(ModerationReasonBodyBuilder b)]) = _$ModerationReasonBody;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModerationReasonBodyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModerationReasonBody> get serializer => _$ModerationReasonBodySerializer();
}

class _$ModerationReasonBodySerializer implements PrimitiveSerializer<ModerationReasonBody> {
  @override
  final Iterable<Type> types = const [ModerationReasonBody, _$ModerationReasonBody];

  @override
  final String wireName = r'ModerationReasonBody';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModerationReasonBody object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModerationReasonBody object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModerationReasonBodyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModerationReasonBody deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModerationReasonBodyBuilder();
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

