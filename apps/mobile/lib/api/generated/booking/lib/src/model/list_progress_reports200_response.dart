//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/api_response_envelope.dart';
import 'package:pguard_booking_api/src/model/progress_report.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_progress_reports200_response.g.dart';

/// ListProgressReports200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class ListProgressReports200Response implements ApiResponseEnvelope, Built<ListProgressReports200Response, ListProgressReports200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<ProgressReport>? get data;

  ListProgressReports200Response._();

  factory ListProgressReports200Response([void updates(ListProgressReports200ResponseBuilder b)]) = _$ListProgressReports200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListProgressReports200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListProgressReports200Response> get serializer => _$ListProgressReports200ResponseSerializer();
}

class _$ListProgressReports200ResponseSerializer implements PrimitiveSerializer<ListProgressReports200Response> {
  @override
  final Iterable<Type> types = const [ListProgressReports200Response, _$ListProgressReports200Response];

  @override
  final String wireName = r'ListProgressReports200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListProgressReports200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(ProgressReport)]),
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
    ListProgressReports200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListProgressReports200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ProgressReport)]),
          ) as BuiltList<ProgressReport>;
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
  ListProgressReports200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListProgressReports200ResponseBuilder();
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

