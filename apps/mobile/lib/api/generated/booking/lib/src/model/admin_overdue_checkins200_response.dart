//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/overdue_checkins_response.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_overdue_checkins200_response.g.dart';

/// AdminOverdueCheckins200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminOverdueCheckins200Response implements ApiResponseEnvelope, Built<AdminOverdueCheckins200Response, AdminOverdueCheckins200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  OverdueCheckinsResponse? get data;

  AdminOverdueCheckins200Response._();

  factory AdminOverdueCheckins200Response([void updates(AdminOverdueCheckins200ResponseBuilder b)]) = _$AdminOverdueCheckins200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminOverdueCheckins200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminOverdueCheckins200Response> get serializer => _$AdminOverdueCheckins200ResponseSerializer();
}

class _$AdminOverdueCheckins200ResponseSerializer implements PrimitiveSerializer<AdminOverdueCheckins200Response> {
  @override
  final Iterable<Type> types = const [AdminOverdueCheckins200Response, _$AdminOverdueCheckins200Response];

  @override
  final String wireName = r'AdminOverdueCheckins200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminOverdueCheckins200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(OverdueCheckinsResponse),
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
    AdminOverdueCheckins200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminOverdueCheckins200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OverdueCheckinsResponse),
          ) as OverdueCheckinsResponse;
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
  AdminOverdueCheckins200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminOverdueCheckins200ResponseBuilder();
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

