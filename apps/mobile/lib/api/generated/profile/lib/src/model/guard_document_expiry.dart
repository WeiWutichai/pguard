//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_document_expiry.g.dart';

/// One credential's expiry date (owner/admin view + edit).
///
/// Properties:
/// * [documentType] 
/// * [expiryDate] 
@BuiltValue()
abstract class GuardDocumentExpiry implements Built<GuardDocumentExpiry, GuardDocumentExpiryBuilder> {
  @BuiltValueField(wireName: r'document_type')
  String get documentType;

  @BuiltValueField(wireName: r'expiry_date')
  Date get expiryDate;

  GuardDocumentExpiry._();

  factory GuardDocumentExpiry([void updates(GuardDocumentExpiryBuilder b)]) = _$GuardDocumentExpiry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardDocumentExpiryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardDocumentExpiry> get serializer => _$GuardDocumentExpirySerializer();
}

class _$GuardDocumentExpirySerializer implements PrimitiveSerializer<GuardDocumentExpiry> {
  @override
  final Iterable<Type> types = const [GuardDocumentExpiry, _$GuardDocumentExpiry];

  @override
  final String wireName = r'GuardDocumentExpiry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardDocumentExpiry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'document_type';
    yield serializers.serialize(
      object.documentType,
      specifiedType: const FullType(String),
    );
    yield r'expiry_date';
    yield serializers.serialize(
      object.expiryDate,
      specifiedType: const FullType(Date),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardDocumentExpiry object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardDocumentExpiryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'document_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.documentType = valueDes;
          break;
        case r'expiry_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.expiryDate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardDocumentExpiry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardDocumentExpiryBuilder();
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

