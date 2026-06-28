//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call_event_type.g.dart';

class CallEventType extends EnumClass {

  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'ringing')
  static const CallEventType ringing = _$ringing;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'accepted')
  static const CallEventType accepted = _$accepted;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'rejected')
  static const CallEventType rejected = _$rejected;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'connected')
  static const CallEventType connected = _$connected;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'ended')
  static const CallEventType ended = _$ended;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'missed')
  static const CallEventType missed = _$missed;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'offer')
  static const CallEventType offer = _$offer;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'answer')
  static const CallEventType answer = _$answer;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'ice_candidate')
  static const CallEventType iceCandidate = _$iceCandidate;
  /// The kind of timeline step. Lifecycle milestones (from the control plane): `ringing`/`accepted`/`rejected`/`connected`/`ended`/`missed`. Signaling steps (observed by the relay): `offer`/`answer`/`ice_candidate` (relayed between peers), `peer_offline` (a frame the peer's socket couldn't receive). 
  @BuiltValueEnumConst(wireName: r'peer_offline')
  static const CallEventType peerOffline = _$peerOffline;

  static Serializer<CallEventType> get serializer => _$callEventTypeSerializer;

  const CallEventType._(String name): super(name);

  static BuiltSet<CallEventType> get values => _$values;
  static CallEventType valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class CallEventTypeMixin = Object with _$CallEventTypeMixin;

