//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_service_request.g.dart';

/// UpdateServiceRequest
///
/// Properties:
/// * [nameTh] 
/// * [nameEn] 
/// * [baseFee] 
/// * [minHours] 
/// * [notes] 
@BuiltValue()
abstract class UpdateServiceRequest implements Built<UpdateServiceRequest, UpdateServiceRequestBuilder> {
  @BuiltValueField(wireName: r'name_th')
  String get nameTh;

  @BuiltValueField(wireName: r'name_en')
  String get nameEn;

  @BuiltValueField(wireName: r'base_fee')
  String get baseFee;

  @BuiltValueField(wireName: r'min_hours')
  int get minHours;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  UpdateServiceRequest._();

  factory UpdateServiceRequest([void updates(UpdateServiceRequestBuilder b)]) = _$UpdateServiceRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateServiceRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateServiceRequest> get serializer => _$UpdateServiceRequestSerializer();
}

class _$UpdateServiceRequestSerializer implements PrimitiveSerializer<UpdateServiceRequest> {
  @override
  final Iterable<Type> types = const [UpdateServiceRequest, _$UpdateServiceRequest];

  @override
  final String wireName = r'UpdateServiceRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateServiceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name_th';
    yield serializers.serialize(
      object.nameTh,
      specifiedType: const FullType(String),
    );
    yield r'name_en';
    yield serializers.serialize(
      object.nameEn,
      specifiedType: const FullType(String),
    );
    yield r'base_fee';
    yield serializers.serialize(
      object.baseFee,
      specifiedType: const FullType(String),
    );
    yield r'min_hours';
    yield serializers.serialize(
      object.minHours,
      specifiedType: const FullType(int),
    );
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateServiceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateServiceRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name_th':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameTh = valueDes;
          break;
        case r'name_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        case r'base_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.baseFee = valueDes;
          break;
        case r'min_hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.minHours = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.notes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateServiceRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateServiceRequestBuilder();
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

