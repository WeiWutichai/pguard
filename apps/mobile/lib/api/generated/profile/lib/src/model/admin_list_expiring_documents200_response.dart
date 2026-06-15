//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/document_expiry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_expiring_documents200_response.g.dart';

/// AdminListExpiringDocuments200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminListExpiringDocuments200Response implements ApiResponseEnvelope, Built<AdminListExpiringDocuments200Response, AdminListExpiringDocuments200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<DocumentExpiry>? get data;

  AdminListExpiringDocuments200Response._();

  factory AdminListExpiringDocuments200Response([void updates(AdminListExpiringDocuments200ResponseBuilder b)]) = _$AdminListExpiringDocuments200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListExpiringDocuments200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListExpiringDocuments200Response> get serializer => _$AdminListExpiringDocuments200ResponseSerializer();
}

class _$AdminListExpiringDocuments200ResponseSerializer implements PrimitiveSerializer<AdminListExpiringDocuments200Response> {
  @override
  final Iterable<Type> types = const [AdminListExpiringDocuments200Response, _$AdminListExpiringDocuments200Response];

  @override
  final String wireName = r'AdminListExpiringDocuments200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListExpiringDocuments200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(DocumentExpiry)]),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminListExpiringDocuments200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListExpiringDocuments200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DocumentExpiry)]),
          ) as BuiltList<DocumentExpiry>;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminListExpiringDocuments200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListExpiringDocuments200ResponseBuilder();
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

