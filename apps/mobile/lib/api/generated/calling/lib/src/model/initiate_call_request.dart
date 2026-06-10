//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_calling_api/src/model/call_type.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'initiate_call_request.g.dart';

/// InitiateCallRequest
///
/// Properties:
/// * [bookingId] - The active booking whose other participant is called (callee derived server-side).
/// * [callType] 
@BuiltValue()
abstract class InitiateCallRequest implements Built<InitiateCallRequest, InitiateCallRequestBuilder> {
  /// The active booking whose other participant is called (callee derived server-side).
  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'call_type')
  CallType? get callType;
  // enum callTypeEnum {  audio,  video,  };

  InitiateCallRequest._();

  factory InitiateCallRequest([void updates(InitiateCallRequestBuilder b)]) = _$InitiateCallRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InitiateCallRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InitiateCallRequest> get serializer => _$InitiateCallRequestSerializer();
}

class _$InitiateCallRequestSerializer implements PrimitiveSerializer<InitiateCallRequest> {
  @override
  final Iterable<Type> types = const [InitiateCallRequest, _$InitiateCallRequest];

  @override
  final String wireName = r'InitiateCallRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InitiateCallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    if (object.callType != null) {
      yield r'call_type';
      yield serializers.serialize(
        object.callType,
        specifiedType: const FullType(CallType),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InitiateCallRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InitiateCallRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'call_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CallType),
          ) as CallType;
          result.callType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InitiateCallRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InitiateCallRequestBuilder();
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

