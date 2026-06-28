//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/overdue_checkin.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'overdue_checkins_response.g.dart';

/// Overdue-check-ins list plus a total count for the dashboard alert badge.
///
/// Properties:
/// * [items] 
/// * [total] - All active jobs with an overdue check-in (independent of the page).
@BuiltValue()
abstract class OverdueCheckinsResponse implements Built<OverdueCheckinsResponse, OverdueCheckinsResponseBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<OverdueCheckin> get items;

  /// All active jobs with an overdue check-in (independent of the page).
  @BuiltValueField(wireName: r'total')
  int get total;

  OverdueCheckinsResponse._();

  factory OverdueCheckinsResponse([void updates(OverdueCheckinsResponseBuilder b)]) = _$OverdueCheckinsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OverdueCheckinsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OverdueCheckinsResponse> get serializer => _$OverdueCheckinsResponseSerializer();
}

class _$OverdueCheckinsResponseSerializer implements PrimitiveSerializer<OverdueCheckinsResponse> {
  @override
  final Iterable<Type> types = const [OverdueCheckinsResponse, _$OverdueCheckinsResponse];

  @override
  final String wireName = r'OverdueCheckinsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OverdueCheckinsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(OverdueCheckin)]),
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
    OverdueCheckinsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OverdueCheckinsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OverdueCheckin)]),
          ) as BuiltList<OverdueCheckin>;
          result.items.replace(valueDes);
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
  OverdueCheckinsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OverdueCheckinsResponseBuilder();
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

