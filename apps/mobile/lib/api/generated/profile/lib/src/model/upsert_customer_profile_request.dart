//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upsert_customer_profile_request.g.dart';

/// UpsertCustomerProfileRequest
///
/// Properties:
/// * [fullName] 
/// * [address] 
@BuiltValue()
abstract class UpsertCustomerProfileRequest implements Built<UpsertCustomerProfileRequest, UpsertCustomerProfileRequestBuilder> {
  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'address')
  String? get address;

  UpsertCustomerProfileRequest._();

  factory UpsertCustomerProfileRequest([void updates(UpsertCustomerProfileRequestBuilder b)]) = _$UpsertCustomerProfileRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpsertCustomerProfileRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpsertCustomerProfileRequest> get serializer => _$UpsertCustomerProfileRequestSerializer();
}

class _$UpsertCustomerProfileRequestSerializer implements PrimitiveSerializer<UpsertCustomerProfileRequest> {
  @override
  final Iterable<Type> types = const [UpsertCustomerProfileRequest, _$UpsertCustomerProfileRequest];

  @override
  final String wireName = r'UpsertCustomerProfileRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpsertCustomerProfileRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
        specifiedType: const FullType(String),
      );
    }
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpsertCustomerProfileRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpsertCustomerProfileRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpsertCustomerProfileRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpsertCustomerProfileRequestBuilder();
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

