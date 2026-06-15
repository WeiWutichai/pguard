//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/access_audit_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_access_audit200_response.g.dart';

/// AdminListAccessAudit200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminListAccessAudit200Response implements ApiResponseEnvelope, Built<AdminListAccessAudit200Response, AdminListAccessAudit200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<AccessAuditEntry>? get data;

  AdminListAccessAudit200Response._();

  factory AdminListAccessAudit200Response([void updates(AdminListAccessAudit200ResponseBuilder b)]) = _$AdminListAccessAudit200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListAccessAudit200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListAccessAudit200Response> get serializer => _$AdminListAccessAudit200ResponseSerializer();
}

class _$AdminListAccessAudit200ResponseSerializer implements PrimitiveSerializer<AdminListAccessAudit200Response> {
  @override
  final Iterable<Type> types = const [AdminListAccessAudit200Response, _$AdminListAccessAudit200Response];

  @override
  final String wireName = r'AdminListAccessAudit200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListAccessAudit200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(AccessAuditEntry)]),
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
    AdminListAccessAudit200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListAccessAudit200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(AccessAuditEntry)]),
          ) as BuiltList<AccessAuditEntry>;
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
  AdminListAccessAudit200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListAccessAudit200ResponseBuilder();
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

