import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/api_error_l10n.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';

void main() {
  group('localizeApiError', () {
    test(
        'transport failure (statusCode null) → localized network message, not raw English',
        () {
      const e = ApiException(
          message: 'Network error — please check your connection',
          statusCode: null);
      expect(localizeApiError(true, e),
          'เครือข่ายขัดข้อง กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต');
      expect(localizeApiError(false, e),
          'Network error — please check your connection');
    });

    test('any 5xx → localized infrastructure message (never the user input)',
        () {
      const e = ApiException(
          message: 'Internal server error',
          code: 'INTERNAL_ERROR',
          statusCode: 500);
      expect(
          localizeApiError(true, e), 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง');
      expect(localizeApiError(false, e),
          'Temporary server problem — please try again later');
      // 503 too.
      expect(
          localizeApiError(
              true, const ApiException(message: 'x', statusCode: 503)),
          'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ภายหลัง');
    });

    test('known OTP sub-code → app-language copy', () {
      const e = ApiException(
          message: 'rejected', code: 'CAPTCHA_INVALID', statusCode: 400);
      expect(localizeApiError(true, e), 'คำตอบไม่ถูกต้อง กรุณาลองอีกครั้ง');
      expect(localizeApiError(false, e),
          'That answer is incorrect — please try again');
    });

    test('unknown code (4xx) → falls back to the server message (never hidden)',
        () {
      const e = ApiException(
          message: 'Booking already has an assigned guard',
          code: 'CONFLICT',
          statusCode: 409);
      expect(
          localizeApiError(true, e), 'Booking already has an assigned guard');
    });
  });
}
