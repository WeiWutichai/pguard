//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'access_audit_entry.g.dart';

/// One PDPA §30 data-access audit row (who accessed what PII, and when).
///
/// Properties:
/// * [id] 
/// * [accessedBy] 
/// * [action] 
/// * [target] 
/// * [accessedAt] 
@BuiltValue()
abstract class AccessAuditEntry implements Built<AccessAuditEntry, AccessAuditEntryBuilder> {
  @BuiltValueField(wireName: r'id')
  int get id;

  @BuiltValueField(wireName: r'accessed_by')
  String get accessedBy;

  @BuiltValueField(wireName: r'action')
  String get action;

  @BuiltValueField(wireName: r'target')
  String? get target;

  @BuiltValueField(wireName: r'accessed_at')
  DateTime get accessedAt;

  AccessAuditEntry._();

  factory AccessAuditEntry([void updates(AccessAuditEntryBuilder b)]) = _$AccessAuditEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AccessAuditEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AccessAuditEntry> get serializer => _$AccessAuditEntrySerializer();
}

class _$AccessAuditEntrySerializer implements PrimitiveSerializer<AccessAuditEntry> {
  @override
  final Iterable<Type> types = const [AccessAuditEntry, _$AccessAuditEntry];

  @override
  final String wireName = r'AccessAuditEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AccessAuditEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(int),
    );
    yield r'accessed_by';
    yield serializers.serialize(
      object.accessedBy,
      specifiedType: const FullType(String),
    );
    yield r'action';
    yield serializers.serialize(
      object.action,
      specifiedType: const FullType(String),
    );
    if (object.target != null) {
      yield r'target';
      yield serializers.serialize(
        object.target,
        specifiedType: const FullType(String),
      );
    }
    yield r'accessed_at';
    yield serializers.serialize(
      object.accessedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AccessAuditEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AccessAuditEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.id = valueDes;
          break;
        case r'accessed_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accessedBy = valueDes;
          break;
        case r'action':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.action = valueDes;
          break;
        case r'target':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.target = valueDes;
          break;
        case r'accessed_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.accessedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AccessAuditEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AccessAuditEntryBuilder();
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

