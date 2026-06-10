//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_rating_api/src/model/admin_reviews.dart';
import 'package:pguard_rating_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_admin_reviews200_response.g.dart';

/// ListAdminReviews200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListAdminReviews200Response implements ApiResponseEnvelope, Built<ListAdminReviews200Response, ListAdminReviews200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  AdminReviews? get data;

  ListAdminReviews200Response._();

  factory ListAdminReviews200Response([void updates(ListAdminReviews200ResponseBuilder b)]) = _$ListAdminReviews200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListAdminReviews200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListAdminReviews200Response> get serializer => _$ListAdminReviews200ResponseSerializer();
}

class _$ListAdminReviews200ResponseSerializer implements PrimitiveSerializer<ListAdminReviews200Response> {
  @override
  final Iterable<Type> types = const [ListAdminReviews200Response, _$ListAdminReviews200Response];

  @override
  final String wireName = r'ListAdminReviews200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListAdminReviews200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(AdminReviews),
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
    ListAdminReviews200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListAdminReviews200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminReviews),
          ) as AdminReviews;
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
  ListAdminReviews200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListAdminReviews200ResponseBuilder();
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

