---
name: pguard-booking-list-tabs-patterns
description: Booking list tabs slice patterns: wallet row vs hero discrepancy, guard earnings logic, Riverpod provider sharing, Payment model field coverage (2026-06-11)
metadata:
  type: project
---

## Slice: feat/booking-list-tabs (2026-06-11)

3 new tab screens: BookingsListScreen (/bookings-history), EarningsScreen (/earnings), WalletScreen (/wallet).

### Key architecture patterns

- `customerHomeControllerProvider` (customer, GET /bookings) and `guardJobsControllerProvider` (guard, GET /bookings) both fetch `/bookings` — earnings screen shares `guardJobsControllerProvider` with guard home (one cache, no duplicate fetch)
- `WalletController` fetches GET /payments; pure statics `spentSatang` / `totalSpentSatang` for money math
- `GuardEarnings` pure class (no Flutter, no HTTP) — jobEarningsSatang = base_fee × hours (guard_count excluded from guard pay; tip excluded — no per-guard tip split in v2)
- `BookingsHistory` pure class — filter + badge logic for the history tab chips

### Money rule applied

- Guard earnings: base_fee × hours (NOT × guard_count, NOT + tip). Labelled "ประมาณการ / Estimated".
- Wallet hero (totalSpentSatang): refunded→0, final_amount wins, else amount−refund_amount clamped ≥0
- Wallet ROW: shows payment.amount (original charge), not spentSatang — intentional design choice (no receipt detail endpoint) but creates hero/row discrepancy for prorated payments

### Known discrepancy (documented, not a bug by design intent)

wallet_screen.dart `_ReceiptRow` line 162 renders `payment.amount` (original charge) while the hero sums `spentSatang(p)` which uses `final_amount` when set. For a prorated-but-completed payment (amount=2000, final_amount=1725, status=completed), the row shows ฿2,000 with "Paid" badge but hero counts ฿1,725. No test covers this case — widget test only tests non-prorated payments.

### Payment model vs contract alignment

- Payment model: id, bookingId, customerId, guardId, amount, expectedTotal, paymentMethod, finalAmount, refundAmount, status, paidAt, createdAt
- Contract adds: updated_at (required but not in Dart model — ignored, fine), actual_hours, refund_status (not in Dart model)
- created_at parsed defensively as nullable; falls back to paidAt for date display

### Route wiring

- /bookings-history → BookingsListScreen (customer only by nav, but route open to guards)
- /wallet → WalletScreen (customer only by nav)
- /earnings → EarningsScreen (guard only by nav)
- No route shadowing with existing /booking/:id/* routes (different path prefix)
- `pg_bottom_nav.dart comingSoon()` helper kept but no longer used by these tabs
