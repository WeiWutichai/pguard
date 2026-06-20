//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_document_expiry_request.g.dart';

/// SetDocumentExpiryRequest
///
/// Properties:
/// * [documentType] - An expiring credential (id_card / security_license / training_cert / criminal_check / driver_license).
/// * [expiryDate] 
@BuiltValue()
abstract class SetDocumentExpiryRequest implements Built<SetDocumentExpiryRequest, SetDocumentExpiryRequestBuilder> {
  /// An expiring credential (id_card / security_license / training_cert / criminal_check / driver_license).
  @BuiltValueField(wireName: r'document_type')
  String get documentType;

  @BuiltValueField(wireName: r'expiry_date')
  Date get expiryDate;

  SetDocumentExpiryRequest._();

  factory SetDocumentExpiryRequest([void updates(SetDocumentExpiryRequestBuilder b)]) = _$SetDocumentExpiryRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetDocumentExpiryRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetDocumentExpiryRequest> get serializer => _$SetDocumentExpiryRequestSerializer();
}

class _$SetDocumentExpiryRequestSerializer implements PrimitiveSerializer<SetDocumentExpiryRequest> {
  @override
  final Iterable<Type> types = const [SetDocumentExpiryRequest, _$SetDocumentExpiryRequest];

  @override
  final String wireName = r'SetDocumentExpiryRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetDocumentExpiryRequest object, {
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
    SetDocumentExpiryRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetDocumentExpiryRequestBuilder result,
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
  SetDocumentExpiryRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetDocumentExpiryRequestBuilder();
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

