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
  // Gateway rate-limit (429) carries no {code} object — key off the status. Plausible behind Thai
  // carrier-NAT where many users share one IP; a raw English 'Rate limit exceeded' was leaking.
  if (status == 429) {
    return isThai
        ? 'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่'
        : 'Too many requests — please wait a moment and try again';
  }
  switch (e.code) {
    case 'PHONE_TAKEN':
      // PATCH /auth/phone: the NEW number is already registered to another account.
      return isThai
          ? 'เบอร์นี้ถูกใช้สมัครแล้ว'
          : 'This phone number is already in use by another account';
    case 'CAPTCHA_INVALID':
      return isThai
          ? 'คำตอบไม่ถูกต้อง กรุณาลองอีกครั้ง'
          : 'That answer is incorrect — please try again';
    case 'CAPTCHA_EXPIRED':
      // The server burns the challenge on TTL lapse; the client already auto-loads a new question.
      return isThai
          ? 'คำถามหมดอายุ ระบบออกคำถามใหม่ให้แล้ว'
          : 'The question expired — a new one has been loaded';
    case 'JOB_TAKEN':
      return isThai
          ? 'งานนี้มีเจ้าหน้าที่รับไปแล้ว'
          : 'This job was already taken by another guard';
    case 'CHECK_IN_WINDOW_CLOSED':
      // G1: a check-in filed past the booked end + 30-min grace (an UPPER bound). Truthfully "the
      // window has closed" (too LATE) — never the old "not time yet" (too early) copy.
      return isThai ? 'หมดเวลาเช็คอินแล้ว' : 'The check-in window has closed';
    case 'START_TOO_EARLY':
      // G3: the guard pressed start before the booking's scheduled time (15-min early grace).
      return isThai
          ? 'ยังไม่ถึงเวลาเริ่มงาน'
          : "It's not time to start this job yet";
    case 'NOT_AT_SITE':
      // G4: the guard tried to mark ARRIVED while outside the 120m meetup geofence. The server
      // message carries the measured distance ("You are {d} m from the meetup point (max 120 m)")
      // — pull the first number for the Thai copy, degrade gracefully when it can't be parsed.
      final d = RegExp(r'\d+').firstMatch(e.message)?.group(0);
      return isThai
          ? (d != null
              ? 'คุณอยู่ห่างจากจุดนัดหมายประมาณ $d ม. — ต้องอยู่ในระยะ 120 ม. จึงจะกดถึงจุดนัดได้'
              : 'คุณยังไม่อยู่ในรัศมีจุดนัดหมาย — เข้าใกล้อีกนิดแล้วลองใหม่')
          : e.message;
    case 'GPS_REQUIRED':
      // G4: a pinned booking marked arrived with no GPS fix (location off/denied). The proximity
      // gate is now at ARRIVAL, so the message speaks of confirming arrival (not starting).
      return isThai
          ? 'ต้องเปิดตำแหน่ง (GPS) เพื่อยืนยันว่าถึงจุดนัดหมายแล้ว — เปิด Location แล้วลองใหม่'
          : 'Turn on Location (GPS) to confirm you have arrived, then try again';
    case 'BOOKING_NOT_PAYABLE':
      return isThai
          ? 'สถานะการจองเปลี่ยนไปแล้ว ไม่ต้องชำระเงิน'
          : 'This booking is no longer awaiting payment';
    case 'BOOKING_CANCELLED':
      return isThai
          ? 'การจองถูกยกเลิกแล้ว ระบบกำลังคืนเงินให้เต็มจำนวน'
          : 'This booking was cancelled — a full refund is on its way';
    case 'SCHEDULED_IN_PAST':
      // C4: the customer tried to book a start time already in the past. The booking form's picker
      // blocks this client-side (min = now); this is the server backstop for a stale form / skewed
      // device clock.
      return isThai
          ? 'เวลาเริ่มงานที่เลือกผ่านไปแล้ว กรุณาเลือกเวลาในอนาคต'
          : 'The selected start time is in the past — please choose a future time';
    case 'CANCEL_REASON_REQUIRED':
      // The cancel/decline body carried no reason (or one that isn't valid for that endpoint) —
      // a client bug or an old build; the screens always pre-select a code.
      return isThai
          ? 'กรุณาเลือกเหตุผลในการยกเลิก'
          : 'Please choose a reason for cancelling';
    case 'CANCEL_NOTE_REQUIRED':
      // Reason "อื่นๆ / Other" needs the free-text note filled in (the screens block this locally;
      // this is the server backstop for an out-of-sync client).
      return isThai
          ? 'เลือก "อื่นๆ" แล้ว กรุณาระบุรายละเอียดเพิ่มเติม'
          : 'Please add a note when the reason is "Other"';
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
