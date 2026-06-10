//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_profile.g.dart';

/// CustomerProfile
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [address] 
@BuiltValue(instantiable: false)
abstract class CustomerProfile  {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomerProfile> get serializer => _$CustomerProfileSerializer();
}

class _$CustomerProfileSerializer implements PrimitiveSerializer<CustomerProfile> {
  @override
  final Iterable<Type> types = const [CustomerProfile];

  @override
  final String wireName = r'CustomerProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
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
    CustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  CustomerProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($CustomerProfile)) as $CustomerProfile;
  }
}

/// a concrete implementation of [CustomerProfile], since [CustomerProfile] is not instantiable
@BuiltValue(instantiable: true)
abstract class $CustomerProfile implements CustomerProfile, Built<$CustomerProfile, $CustomerProfileBuilder> {
  $CustomerProfile._();

  factory $CustomerProfile([void Function($CustomerProfileBuilder)? updates]) = _$$CustomerProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($CustomerProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$CustomerProfile> get serializer => _$$CustomerProfileSerializer();
}

class _$$CustomerProfileSerializer implements PrimitiveSerializer<$CustomerProfile> {
  @override
  final Iterable<Type> types = const [$CustomerProfile, _$$CustomerProfile];

  @override
  final String wireName = r'$CustomerProfile';

  @override
  Object serialize(
    Serializers serializers,
    $CustomerProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(CustomerProfile))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomerProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
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
  $CustomerProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $CustomerProfileBuilder();
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

