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

    test('gateway 429 (bare string, no code) → localized rate-limit message',
        () {
      const e = ApiException(message: 'Rate limit exceeded', statusCode: 429);
      expect(localizeApiError(true, e),
          'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่');
    });

    test('the new typed backend codes are localized (TH)', () {
      String th(String code) => localizeApiError(
          true, ApiException(message: 'x', code: code, statusCode: 409));
      expect(th('JOB_TAKEN'), 'งานนี้มีเจ้าหน้าที่รับไปแล้ว');
      expect(th('BOOKING_NOT_PAYABLE'),
          'สถานะการจองเปลี่ยนไปแล้ว ไม่ต้องชำระเงิน');
      expect(th('BOOKING_CANCELLED'),
          'การจองถูกยกเลิกแล้ว ระบบกำลังคืนเงินให้เต็มจำนวน');
      expect(
          localizeApiError(
              true,
              const ApiException(
                  message: 'x', code: 'CAPTCHA_EXPIRED', statusCode: 400)),
          'คำถามหมดอายุ ระบบออกคำถามใหม่ให้แล้ว');
    });

    test(
        'C4: SCHEDULED_IN_PAST → localized "pick a future time" message (TH + EN)',
        () {
      const e = ApiException(
          message: 'scheduled_at is in the past',
          code: 'SCHEDULED_IN_PAST',
          statusCode: 400);
      expect(localizeApiError(true, e),
          'เวลาเริ่มงานที่เลือกผ่านไปแล้ว กรุณาเลือกเวลาในอนาคต');
      expect(localizeApiError(false, e),
          'The selected start time is in the past — please choose a future time');
    });

    test('G1/G3 guard-lifecycle codes localize by code (TH + EN)', () {
      String th(String code) => localizeApiError(true,
          ApiException(message: 'raw english', code: code, statusCode: 409));
      String en(String code) => localizeApiError(false,
          ApiException(message: 'raw english', code: code, statusCode: 409));
      // G1 — check-in past the booked end + grace: "the window has closed" (too late).
      expect(th('CHECK_IN_WINDOW_CLOSED'), 'หมดเวลาเช็คอินแล้ว');
      expect(en('CHECK_IN_WINDOW_CLOSED'), 'The check-in window has closed');
      // G3 — start pressed before the scheduled window opened.
      expect(th('START_TOO_EARLY'), 'ยังไม่ถึงเวลาเริ่มงาน');
      expect(en('START_TOO_EARLY'), "It's not time to start this job yet");
    });
  });
}
