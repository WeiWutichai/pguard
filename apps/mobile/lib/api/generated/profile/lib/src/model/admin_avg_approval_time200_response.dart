//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/avg_approval_time.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_avg_approval_time200_response.g.dart';

/// AdminAvgApprovalTime200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminAvgApprovalTime200Response implements ApiResponseEnvelope, Built<AdminAvgApprovalTime200Response, AdminAvgApprovalTime200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  AvgApprovalTime? get data;

  AdminAvgApprovalTime200Response._();

  factory AdminAvgApprovalTime200Response([void updates(AdminAvgApprovalTime200ResponseBuilder b)]) = _$AdminAvgApprovalTime200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminAvgApprovalTime200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminAvgApprovalTime200Response> get serializer => _$AdminAvgApprovalTime200ResponseSerializer();
}

class _$AdminAvgApprovalTime200ResponseSerializer implements PrimitiveSerializer<AdminAvgApprovalTime200Response> {
  @override
  final Iterable<Type> types = const [AdminAvgApprovalTime200Response, _$AdminAvgApprovalTime200Response];

  @override
  final String wireName = r'AdminAvgApprovalTime200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminAvgApprovalTime200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(AvgApprovalTime),
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
    AdminAvgApprovalTime200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminAvgApprovalTime200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AvgApprovalTime),
          ) as AvgApprovalTime;
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
  AdminAvgApprovalTime200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminAvgApprovalTime200ResponseBuilder();
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

