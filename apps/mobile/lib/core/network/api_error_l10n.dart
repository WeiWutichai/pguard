import 'api_exception.dart';

/// Localize an [ApiException] to the app's language. Fixes the class of bugs where raw ENGLISH
/// server/transport text leaked into the (default) Thai UI. Pure + testable: callers pass `isThai`
/// (the app-wide `ref.read(localeControllerProvider) == AppLocale.th`).
///
/// Handles the CROSS-CUTTING cases every screen hits:
///  - transport failure (offline / timeout / DNS → `statusCode == null`): the single biggest leak —
///    the Dio client throws a hardcoded English "Network error…" that surfaced verbatim everywhere.
///  - any 5xx: infrastructure (SMS gateway/credits, DB, cache) — NEVER the user's input; the raw
///    "INTERNAL_ERROR" text read as if the user did something wrong.
///  - the OTP/captcha sub-codes (locale-independent codes from services/otp) → app-language copy.
///
/// An UNMAPPED code falls back to the server's own already-generic `message` (unchanged behaviour) —
/// so a specific, useful domain message is never hidden behind a generic string.
String localizeApiError(bool isThai, ApiException e) {
  if (e.isNetwork) {
    return isThai
        ? 'เครือข่ายขัดข้อง กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต'
        : 'Network error — please check your connection';
  }
  final status = e.statusCode;
  if (status != null && status >= 500) {
    return isThai
        ? 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง'
        : 'Temporary server problem — please try again later';
  }
  switch (e.code) {
    case 'CAPTCHA_INVALID':
      return isThai
          ? 'คำตอบไม่ถูกต้อง กรุณาลองอีกครั้ง'
          : 'That answer is incorrect — please try again';
    case 'OTP_COOLDOWN':
      return isThai
          ? 'กรุณารอสักครู่ก่อนขอรหัสใหม่'
          : 'Please wait a moment before requesting another code';
    case 'OTP_BURST_LOCK':
      return isThai
          ? 'ขอรหัส OTP บ่อยเกินไป กรุณาลองใหม่ในภายหลัง'
          : 'Too many OTP requests — please try again later';
    case 'OTP_ADMIN_LOCK':
      return isThai
          ? 'ขอรหัส OTP เกินจำนวนที่กำหนด กรุณาติดต่อเจ้าหน้าที่'
          : 'OTP request limit reached — please contact support';
    case 'OTP_INVALID':
      return isThai
          ? 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ'
          : 'The OTP is incorrect or has expired';
    case 'OTP_MAX_ATTEMPTS':
      return isThai
          ? 'กรอกรหัสผิดเกินจำนวนครั้ง กรุณาขอรหัสใหม่'
          : 'Too many attempts — please request a new OTP';
    default:
      return e.message;
  }
}
