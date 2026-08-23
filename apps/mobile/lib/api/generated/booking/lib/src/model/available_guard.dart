//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/guard_documents.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'available_guard.g.dart';

/// An approved guard (profile catalog) enriched with their rating summary (rating). `display_name` + `avatar_url` are the same approved-guard exposure as `GET /guards/{id}/public` — the guard the customer is choosing — so the selection card shows a real name + photo instead of an id + initials. Both are omitted when absent (`avatar_url` is a short-lived presigned GET URL, null/omitted when no avatar is set). `has_documents` says WHETHER the guard's five credential documents are on file (profile-derived boolean) — the documents themselves are never exposed to customers. OMITTED when unknown (an older profile that doesn't emit the field), so a client must render \"unknown\" as nothing, never as \"no documents\".
///
/// Properties:
/// * [guardId] 
/// * [displayName] - Guard's full name for the selection card; null/omitted if not set.
/// * [avatarUrl] - Short-lived presigned GET URL for the guard's photo; null/omitted if no avatar.
/// * [yearsOfExperience] 
/// * [averageRating] - AVG of visible overall ratings (decimal string); null if none / rating unreachable.
/// * [reviewCount] 
/// * [hasDocuments] - True when all five credential documents (id card, security license, training cert, criminal check, driver license) are on file with profile; omitted when unknown.
/// * [documents] 
/// * [distanceM] - Straight-line distance (meters) from the guard's LIVE position to the meetup point — present ONLY when the request supplied `lat`/`lng` AND the guard's live position is known (the list is then sorted by it ascending). Omitted otherwise.
@BuiltValue()
abstract class AvailableGuard implements Built<AvailableGuard, AvailableGuardBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// Guard's full name for the selection card; null/omitted if not set.
  @BuiltValueField(wireName: r'display_name')
  String? get displayName;

  /// Short-lived presigned GET URL for the guard's photo; null/omitted if no avatar.
  @BuiltValueField(wireName: r'avatar_url')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  /// AVG of visible overall ratings (decimal string); null if none / rating unreachable.
  @BuiltValueField(wireName: r'average_rating')
  String? get averageRating;

  @BuiltValueField(wireName: r'review_count')
  int get reviewCount;

  /// True when all five credential documents (id card, security license, training cert, criminal check, driver license) are on file with profile; omitted when unknown.
  @BuiltValueField(wireName: r'has_documents')
  bool? get hasDocuments;

  @BuiltValueField(wireName: r'documents')
  GuardDocuments? get documents;

  /// Straight-line distance (meters) from the guard's LIVE position to the meetup point — present ONLY when the request supplied `lat`/`lng` AND the guard's live position is known (the list is then sorted by it ascending). Omitted otherwise.
  @BuiltValueField(wireName: r'distance_m')
  double? get distanceM;

  AvailableGuard._();

  factory AvailableGuard([void updates(AvailableGuardBuilder b)]) = _$AvailableGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvailableGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvailableGuard> get serializer => _$AvailableGuardSerializer();
}

class _$AvailableGuardSerializer implements PrimitiveSerializer<AvailableGuard> {
  @override
  final Iterable<Type> types = const [AvailableGuard, _$AvailableGuard];

  @override
  final String wireName = r'AvailableGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvailableGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.displayName != null) {
      yield r'display_name';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatar_url';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
    if (object.averageRating != null) {
      yield r'average_rating';
      yield serializers.serialize(
        object.averageRating,
        specifiedType: const FullType(String),
      );
    }
    yield r'review_count';
    yield serializers.serialize(
      object.reviewCount,
      specifiedType: const FullType(int),
    );
    if (object.hasDocuments != null) {
      yield r'has_documents';
      yield serializers.serialize(
        object.hasDocuments,
        specifiedType: const FullType(bool),
      );
    }
    if (object.documents != null) {
      yield r'documents';
      yield serializers.serialize(
        object.documents,
        specifiedType: const FullType(GuardDocuments),
      );
    }
    if (object.distanceM != null) {
      yield r'distance_m';
      yield serializers.serialize(
        object.distanceM,
        specifiedType: const FullType(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AvailableGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AvailableGuardBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'display_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'avatar_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'average_rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.averageRating = valueDes;
          break;
        case r'review_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        case r'has_documents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasDocuments = valueDes;
          break;
        case r'documents':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(GuardDocuments),
          ) as GuardDocuments;
          result.documents.replace(valueDes);
          break;
        case r'distance_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.distanceM = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvailableGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvailableGuardBuilder();
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

