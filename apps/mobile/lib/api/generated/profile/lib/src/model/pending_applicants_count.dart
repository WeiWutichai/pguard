//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pending_applicants_count.g.dart';

/// Counts of guards + customers awaiting admin approval (the dashboard new-applicants badge + the ผู้สมัคร page tabs). `total = guards + customers`. 
///
/// Properties:
/// * [guards] 
/// * [customers] 
/// * [total] 
@BuiltValue()
abstract class PendingApplicantsCount implements Built<PendingApplicantsCount, PendingApplicantsCountBuilder> {
  @BuiltValueField(wireName: r'guards')
  int get guards;

  @BuiltValueField(wireName: r'customers')
  int get customers;

  @BuiltValueField(wireName: r'total')
  int get total;

  PendingApplicantsCount._();

  factory PendingApplicantsCount([void updates(PendingApplicantsCountBuilder b)]) = _$PendingApplicantsCount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PendingApplicantsCountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PendingApplicantsCount> get serializer => _$PendingApplicantsCountSerializer();
}

class _$PendingApplicantsCountSerializer implements PrimitiveSerializer<PendingApplicantsCount> {
  @override
  final Iterable<Type> types = const [PendingApplicantsCount, _$PendingApplicantsCount];

  @override
  final String wireName = r'PendingApplicantsCount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PendingApplicantsCount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guards';
    yield serializers.serialize(
      object.guards,
      specifiedType: const FullType(int),
    );
    yield r'customers';
    yield serializers.serialize(
      object.customers,
      specifiedType: const FullType(int),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PendingApplicantsCount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PendingApplicantsCountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guards':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.guards = valueDes;
          break;
        case r'customers':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.customers = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PendingApplicantsCount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PendingApplicantsCountBuilder();
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

