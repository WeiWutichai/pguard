//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/customer_profile.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'my_customer_profile.g.dart';

/// MyCustomerProfile
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [address] 
/// * [companyName] 
/// * [email] 
/// * [contactPhone] 
/// * [kind] 
@BuiltValue()
abstract class MyCustomerProfile implements CustomerProfile, Built<MyCustomerProfile, MyCustomerProfileBuilder> {
  @BuiltValueField(wireName: r'kind')
  MyCustomerProfileKindEnum get kind;
  // enum kindEnum {  customer,  };

  MyCustomerProfile._();

  factory MyCustomerProfile([void updates(MyCustomerProfileBuilder b)]) = _$MyCustomerProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MyCustomerProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MyCustomerProfile> get serializer => _$MyCustomerProfileSerializer();
}

class _$MyCustomerProfileSerializer implements PrimitiveSerializer<MyCustomerProfile> {
  @override
  final Iterable<Type> types = const [MyCustomerProfile, _$MyCustomerProfile];

  @override
  final String wireName = r'MyCustomerProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MyCustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(MyCustomerProfileKindEnum),
    );
    if (object.companyName != null) {
      yield r'company_name';
      yield serializers.serialize(
        object.companyName,
        specifiedType: const FullType(String),
      );
    }
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
        specifiedType: const FullType(String),
      );
    }
    if (object.contactPhone != null) {
      yield r'contact_phone';
      yield serializers.serialize(
        object.contactPhone,
        specifiedType: const FullType(String),
      );
    }
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MyCustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MyCustomerProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MyCustomerProfileKindEnum),
          ) as MyCustomerProfileKindEnum;
          result.kind = valueDes;
          break;
        case r'company_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.companyName = valueDes;
          break;
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'contact_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.contactPhone = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MyCustomerProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MyCustomerProfileBuilder();
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

class MyCustomerProfileKindEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'customer')
  static const MyCustomerProfileKindEnum customer = _$myCustomerProfileKindEnum_customer;

  static Serializer<MyCustomerProfileKindEnum> get serializer => _$myCustomerProfileKindEnumSerializer;

  const MyCustomerProfileKindEnum._(String name): super(name);

  static BuiltSet<MyCustomerProfileKindEnum> get values => _$myCustomerProfileKindEnumValues;
  static MyCustomerProfileKindEnum valueOf(String name) => _$myCustomerProfileKindEnumValueOf(name);
}

