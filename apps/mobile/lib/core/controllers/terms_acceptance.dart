import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The terms version this device's user accepted in THIS session (`null` = not accepted).
///
/// Registration is gated on it: the customer/guard registration paths must not create an account (or
/// enrol an added role) until the terms screen has returned an acceptance. Kept in memory and
/// cleared on logout — acceptance is personal, so the next account on this device must accept for
/// itself, and it is never persisted as a device-wide "already agreed" flag. Within one registration
/// run it stops the screen re-asking on every retry.
final termsAcceptedVersionProvider = StateProvider<String?>((ref) => null);
