/// A normalized API error surfaced to controllers/UI. Built from the gateway/service error
/// envelope `{ error: { code, message } }` (or a transport failure). Never carries secrets;
/// `message` is the server's already-generic text.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
  });

  /// Human-readable, already-generic message (safe to show).
  final String message;

  /// Server error code, e.g. `BAD_REQUEST`, `UNAUTHORIZED`. `null` for transport errors.
  final String? code;

  /// HTTP status, when there was a response.
  final int? statusCode;

  /// Network/transport failure (no HTTP response): timeouts, DNS, connection refused.
  bool get isNetwork => statusCode == null;

  /// Authentication failure that refresh could not resolve.
  bool get isUnauthorized => statusCode == 401;

  /// A `409 Conflict` — the resource's current state forbids the write. For chat, the chat
  /// service returns this when the conversation is READ-ONLY (its booking is completed/cancelled),
  /// so the send/upload paths can surface the localized "job ended" message instead of a generic
  /// transport error. Distinct from [isNetwork]: a 409 carried an HTTP response, a network error
  /// did not.
  bool get isConflict => statusCode == 409;

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ' $code' : ''}): $message';
}
