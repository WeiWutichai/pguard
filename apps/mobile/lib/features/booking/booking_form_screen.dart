import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/location/place_search_service.dart';
import '../../core/models/booking_options.dart';
import '../../core/models/geo.dart';
import '../../core/models/money.dart';
import '../../core/permissions/permission_gate.dart';
import '../../core/providers.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/pg_map.dart';
import 'widgets/place_search_field.dart';

/// Step 2 — the rich booking form (mockup #65). Top-to-bottom: service-time (start/end + quick
/// presets, computing whole hours), location (real OSM [PgMap] + Nominatim place search + use-my-
/// location + editable address + an extra-details note), security-equipment and add-on-service
/// checkbox groups, guard-count stepper, tip, a live price breakdown, then "ค้นหาเจ้าหน้าที่".
///
/// The backend `POST /v1/bookings` is UNCHANGED: the start maps to `scheduled_at`, the computed
/// `(end − start)` whole hours map to `hours`, and the extra-detail fields are FOLDED INTO the
/// free-text `address` (see [composeAddress]). The price shown is an ESTIMATE
/// (`base_fee × hours × guards + tip`); the authoritative figure rides the created booking.
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  /// Quick-duration presets (whole hours). "กำหนดเอง" (custom) is a separate chip that opens the
  /// end picker rather than setting a fixed length.
  static const List<int> _durationPresets = [12, 8, 4];

  late final TextEditingController _address = TextEditingController(
    text: ref.read(bookingFlowControllerProvider).address,
  );
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _details = TextEditingController(
    text: ref.read(bookingFlowControllerProvider).extraDetails,
  );

  bool _resolving = false; // reverse-geocoding the current-location fix

  BookingFlowController get _ctrl =>
      ref.read(bookingFlowControllerProvider.notifier);

  @override
  void dispose() {
    _address.dispose();
    _search.dispose();
    _details.dispose();
    super.dispose();
  }

  /// A place-search hit (Nominatim): drop the pin, set lat/lng, fill the address.
  void _onPlaceSelected(PlaceResult result) {
    _ctrl.setLocation(result.toGeoPlace());
    _syncAddress(result.displayName);
  }

  /// A tap on the map: move the pin, then reverse-geocode for the address (best-effort; falls back
  /// to the coordinate label). Stale-guarded by re-checking the pin after the await.
  Future<void> _onMapTap(GeoPoint point) async {
    _ctrl.setLocation(GeoPlace(point: point, placeName: point.label));
    _syncAddress(point.label);
    await _reverseGeocode(point);
  }

  Future<void> _useCurrentLocation() async {
    final status = await ref.read(permissionGateProvider).locationStatus();
    if (status != PgPermissionState.granted && mounted) {
      await context.push('/permissions/location');
    }
    if (!mounted) return;
    final fix = await ref.read(locationServiceProvider).currentLocation() ??
        GeoPoint.bangkok;
    _ctrl.setLocation(GeoPlace(point: fix, placeName: fix.label));
    _syncAddress(fix.label);
    await _reverseGeocode(fix);
  }

  /// Reverse-geocode [point] to a human place name and fold it back into the address/pin — but
  /// only if the pin hasn't moved on since (stale-guard).
  Future<void> _reverseGeocode(GeoPoint point) async {
    setState(() => _resolving = true);
    final name = await ref.read(locationServiceProvider).reverseGeocode(point);
    if (!mounted) return;
    setState(() => _resolving = false);
    final current = ref.read(bookingFlowControllerProvider).place?.point;
    if (current != point) return; // pin moved while we awaited — discard
    _ctrl.setLocation(GeoPlace(point: point, placeName: name));
    _syncAddress(name);
  }

  void _syncAddress(String text) {
    _address.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _pickDateTime({
    required DateTime initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay(hour: initial.hour, minute: initial.minute);
    onPicked(DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  /// "ค้นหาเจ้าหน้าที่" / Find guards — does NOT create the booking. Discovery's
  /// `GET /v1/available-guards` lists approved+online guards without a created booking, so the
  /// job (and its broadcast to guards) is held back until the customer taps "ยืนยันการจอง" on the
  /// discovery screen (fixes #79: guards no longer see the job at the form step). The booking_flow
  /// state (service/place/time/etc.) lives in the keepAlive controller and carries across.
  void _submit() => context.push('/book/guards');

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(bookingFlowControllerProvider);
    final service = state.service;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'จองเจ้าหน้าที่' : 'Book a guard',
        subtitle: service != null
            ? service.name(isThai)
            : (isThai ? 'การจอง' : 'Booking'),
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PgTokens.space4),
                children: [
                  // 1 — ประเภทสถานที่ / place type (the kind of site → folded into the address)
                  _Section(
                    title: isThai ? 'ประเภทสถานที่' : 'Place type',
                    child: Wrap(
                      spacing: PgTokens.space2,
                      runSpacing: PgTokens.space2,
                      children: [
                        for (final pt in kPlaceTypes)
                          _PlaceTypeChip(
                            label: pt.label(isThai),
                            icon: _placeTypeIcon(pt.id),
                            selected: state.placeTypeId == pt.id,
                            onTap: () => _ctrl.setPlaceType(pt.id),
                          ),
                      ],
                    ),
                  ),
                  // 2 — ระยะเวลาบริการ / time
                  _Section(
                    title: isThai ? 'ระยะเวลาบริการ' : 'Service time',
                    child: _TimeSection(
                      state: state,
                      isThai: isThai,
                      presets: _durationPresets,
                      onPreset: _ctrl.setDurationPreset,
                      onPickStart: () => _pickDateTime(
                        initial: state.startAt ??
                            DateTime.now().add(const Duration(hours: 1)),
                        onPicked: _ctrl.setStart,
                      ),
                      onPickEnd: () => _pickDateTime(
                        initial: state.endAt ??
                            (state.startAt ?? DateTime.now())
                                .add(Duration(hours: state.minHours)),
                        onPicked: _ctrl.setEnd,
                      ),
                    ),
                  ),
                  // 3 — สถานที่ / location
                  _Section(
                    title: isThai ? 'สถานที่' : 'Location',
                    child: _LocationSection(
                      state: state,
                      isThai: isThai,
                      addressController: _address,
                      searchController: _search,
                      detailsController: _details,
                      resolving: _resolving,
                      onPlaceSelected: _onPlaceSelected,
                      onMapTap: _onMapTap,
                      onUseCurrent: _useCurrentLocation,
                      onAddressChanged: _ctrl.setAddress,
                      onDetailsChanged: _ctrl.setExtraDetails,
                    ),
                  ),
                  // 4 — อุปกรณ์รักษาความปลอดภัย / security equipment
                  _Section(
                    title:
                        isThai ? 'อุปกรณ์รักษาความปลอดภัย' : 'Security equipment',
                    child: _CheckboxGroup(
                      options: kSecurityEquipment,
                      selected: state.equipment,
                      isThai: isThai,
                      onToggle: _ctrl.toggleEquipment,
                    ),
                  ),
                  // 5 — บริการเพิ่มเติม / add-on services
                  _Section(
                    title: isThai ? 'บริการเพิ่มเติม' : 'Add-on services',
                    child: _CheckboxGroup(
                      options: kAddOnServices,
                      selected: state.addOns,
                      isThai: isThai,
                      onToggle: _ctrl.toggleAddOn,
                    ),
                  ),
                  // 6 — จำนวนเจ้าหน้าที่ / guard count
                  _Section(
                    title: isThai ? 'จำนวนเจ้าหน้าที่' : 'Number of guards',
                    child: _Stepper(
                      value: state.guardCount,
                      min: 1,
                      max: 20,
                      unit: isThai ? 'คน' : 'guards',
                      onChanged: _ctrl.setGuardCount,
                    ),
                  ),
                  // 7 — ทิป / tip
                  _Section(
                    title: isThai ? 'ทิป' : 'Tip',
                    child: _TipSection(
                      selected: state.tipSatang,
                      isThai: isThai,
                      onSelect: _ctrl.setTipSatang,
                    ),
                  ),
                  // 8 — price breakdown
                  _PriceBreakdown(state: state, isThai: isThai),
                  if (state.error != null) ...[
                    const SizedBox(height: PgTokens.space3),
                    Text(state.error!,
                        style: const TextStyle(color: PgTokens.colorDanger)),
                  ],
                ],
              ),
            ),
            // 9 — CTA
            Container(
              padding: const EdgeInsets.all(PgTokens.space4),
              decoration: const BoxDecoration(
                color: PgTokens.colorSurface,
                border: Border(top: BorderSide(color: PgTokens.colorBorder)),
              ),
              child: SafeArea(
                top: false,
                child: PgPrimaryButton(
                  // Navigation only — the booking is created later, on "ยืนยันการจอง" at
                  // discovery (fixes #79), so there is no network call / busy state here.
                  label: isThai ? 'ค้นหาเจ้าหน้าที่' : 'Find guards',
                  onPressed: _submit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled form section card — the consistent block framing for every group on the form.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: PgTokens.space4),
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorText)),
          const SizedBox(height: PgTokens.space3),
          child,
        ],
      ),
    );
  }
}

// ── 2 — Service-time section ────────────────────────────────────────────────────────────────

class _TimeSection extends StatelessWidget {
  const _TimeSection({
    required this.state,
    required this.isThai,
    required this.presets,
    required this.onPreset,
    required this.onPickStart,
    required this.onPickEnd,
  });

  final BookingFlowState state;
  final bool isThai;
  final List<int> presets;
  final ValueChanged<int> onPreset;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;

  @override
  Widget build(BuildContext context) {
    final hours = state.hours;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: PgTokens.space2,
          runSpacing: PgTokens.space2,
          children: [
            for (final p in presets)
              _PillChip(
                label: '$p ${isThai ? 'ชม.' : 'hrs'}',
                selected: hours == p && state.startAt != null,
                onTap: () => onPreset(p),
              ),
            _PillChip(
              label: isThai ? 'กำหนดเอง' : 'Custom',
              selected: state.startAt != null && !presets.contains(hours),
              onTap: onPickEnd,
            ),
          ],
        ),
        const SizedBox(height: PgTokens.space3),
        _DateTimeRow(
          label: isThai ? 'เริ่ม' : 'Start',
          when: state.startAt,
          onTap: onPickStart,
          isThai: isThai,
        ),
        const SizedBox(height: PgTokens.space2),
        _DateTimeRow(
          label: isThai ? 'สิ้นสุด' : 'End',
          when: state.endAt,
          onTap: onPickEnd,
          isThai: isThai,
        ),
        const SizedBox(height: PgTokens.space3),
        Row(
          children: [
            const Icon(Icons.schedule, size: 16, color: PgTokens.colorPrimary),
            const SizedBox(width: PgTokens.space2),
            Text(
              isThai
                  ? 'ระยะเวลาบริการ: $hours ชั่วโมง'
                  : 'Service time: $hours hours',
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorText),
            ),
          ],
        ),
        if (state.startAt != null && state.endAt != null && !state.meetsMinHours) ...[
          const SizedBox(height: PgTokens.space2),
          _InlineWarning(
            text: isThai
                ? 'ขั้นต่ำ ${state.minHours} ชม.'
                : 'Minimum ${state.minHours} hrs',
          ),
        ],
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.when,
    required this.onTap,
    required this.isThai,
  });

  final String label;
  final DateTime? when;
  final VoidCallback onTap;
  final bool isThai;

  String _format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final suffix = isThai ? ' น.' : '';
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            border: Border.all(color: PgTokens.colorBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 16, color: PgTokens.colorPrimary),
              const SizedBox(width: PgTokens.space3),
              SizedBox(
                width: 48,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorTextMuted)),
              ),
              Expanded(
                child: Text(
                  when != null
                      ? _format(when!)
                      : (isThai ? 'เลือกวันและเวลา' : 'Pick date & time'),
                  style: TextStyle(
                    fontSize: 14,
                    color: when != null
                        ? PgTokens.colorText
                        : PgTokens.colorTextMuted,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: PgTokens.colorTextFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 3 — Location section ────────────────────────────────────────────────────────────────────

class _LocationSection extends StatelessWidget {
  const _LocationSection({
    required this.state,
    required this.isThai,
    required this.addressController,
    required this.searchController,
    required this.detailsController,
    required this.resolving,
    required this.onPlaceSelected,
    required this.onMapTap,
    required this.onUseCurrent,
    required this.onAddressChanged,
    required this.onDetailsChanged,
  });

  final BookingFlowState state;
  final bool isThai;
  final TextEditingController addressController;
  final TextEditingController searchController;
  final TextEditingController detailsController;
  final bool resolving;
  final ValueChanged<PlaceResult> onPlaceSelected;
  final ValueChanged<GeoPoint> onMapTap;
  final VoidCallback onUseCurrent;
  final ValueChanged<String> onAddressChanged;
  final ValueChanged<String> onDetailsChanged;

  @override
  Widget build(BuildContext context) {
    final point = state.place?.point ?? GeoPoint.bangkok;
    final hasPin = state.place != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlaceSearchField(
          controller: searchController,
          isThai: isThai,
          onSelected: onPlaceSelected,
        ),
        const SizedBox(height: PgTokens.space3),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PgMap(
            // PgMap re-centres on the picked coordinate imperatively (didUpdateWidget) — not
            // re-keyed, so the map + TileLayer persist across taps (no tile re-fetch / flicker).
            center: point,
            initialZoom: 15,
            borderRadius: PgTokens.radiusXl,
            onTap: onMapTap,
            markers: hasPin
                ? [
                    PgMarker(
                      point: point,
                      width: 36,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const _Pin(),
                    ),
                  ]
                : const [],
          ),
        ),
        const SizedBox(height: PgTokens.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: resolving ? null : onUseCurrent,
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(isThai ? 'ใช้ตำแหน่งปัจจุบัน' : 'Use current location'),
            style: TextButton.styleFrom(foregroundColor: PgTokens.colorPrimary),
          ),
        ),
        const SizedBox(height: PgTokens.space2),
        TextField(
          controller: addressController,
          onChanged: onAddressChanged,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: isThai ? 'ที่อยู่' : 'Address',
            hintText: isThai
                ? 'บ้านเลขที่ ถนน แขวง เขต'
                : 'House no., street, sub-district, district',
            prefixIcon: const Icon(Icons.location_on_outlined),
          ),
        ),
        const SizedBox(height: PgTokens.space3),
        TextField(
          controller: detailsController,
          onChanged: onDetailsChanged,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: isThai ? 'รายละเอียดเพิ่มเติม' : 'Extra details',
            hintText: isThai
                ? 'จุดสังเกต ทางเข้า ข้อกำหนดพิเศษ ฯลฯ'
                : 'Landmarks, entrance, special instructions, etc.',
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: PgTokens.colorPrimary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield, color: Colors.white, size: 18),
        ),
        Container(width: 2, height: 10, color: PgTokens.colorPrimary),
      ],
    );
  }
}

// ── 4 & 5 — Checkbox groups ─────────────────────────────────────────────────────────────────

class _CheckboxGroup extends StatelessWidget {
  const _CheckboxGroup({
    required this.options,
    required this.selected,
    required this.isThai,
    required this.onToggle,
  });

  final List<BookingExtra> options;
  final Set<String> selected;
  final bool isThai;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final o in options)
          InkWell(
            onTap: () => onToggle(o.id),
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: PgTokens.space1),
              child: Row(
                children: [
                  Checkbox(
                    value: selected.contains(o.id),
                    onChanged: (_) => onToggle(o.id),
                    activeColor: PgTokens.colorPrimary,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: Text(o.label(isThai),
                        style: const TextStyle(
                            fontSize: 14, color: PgTokens.colorText)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── 6 — Guard-count stepper ─────────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundButton(
          icon: Icons.remove,
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        _RoundButton(
          icon: Icons.add,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? PgTokens.colorGreen50 : PgTokens.colorSunken,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon,
              color: enabled ? PgTokens.colorPrimary : PgTokens.colorTextFaint,
              size: 20),
        ),
      ),
    );
  }
}

// ── 7 — Tip ─────────────────────────────────────────────────────────────────────────────────

class _TipSection extends StatelessWidget {
  const _TipSection({
    required this.selected,
    required this.isThai,
    required this.onSelect,
  });

  static const List<int> _presets = [0, 5000, 10000]; // satang: ฿0 / ฿50 / ฿100

  final int selected;
  final bool isThai;
  final ValueChanged<int> onSelect;

  Future<void> _promptCustom(BuildContext context) async {
    final input = TextEditingController();
    final satang = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isThai ? 'ระบุทิป' : 'Custom tip'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: '฿ ',
            labelText: isThai ? 'จำนวนเงิน (บาท)' : 'Amount (THB)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, Money.satangFromString(input.text)),
            child: Text(isThai ? 'ตกลง' : 'OK'),
          ),
        ],
      ),
    );
    input.dispose();
    if (satang != null) onSelect(satang);
  }

  @override
  Widget build(BuildContext context) {
    final customActive = !_presets.contains(selected);
    return Wrap(
      spacing: PgTokens.space2,
      runSpacing: PgTokens.space2,
      children: [
        for (final tip in _presets)
          _PillChip(
            label: Money.format(tip),
            selected: tip == selected,
            onTap: () => onSelect(tip),
          ),
        _PillChip(
          label: customActive
              ? Money.format(selected)
              : (isThai ? 'ระบุ' : 'Custom'),
          selected: customActive,
          onTap: () => _promptCustom(context),
        ),
      ],
    );
  }
}

// ── 8 — Price breakdown ─────────────────────────────────────────────────────────────────────

class _PriceBreakdown extends StatelessWidget {
  const _PriceBreakdown({required this.state, required this.isThai});

  final BookingFlowState state;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final hourly = state.estimateHourlySatang;
    final hours = state.hours;
    final guards = state.guardCount;
    final base = hourly * hours; // per-guard line
    final tip = state.tipSatang;
    final total = base * guards + tip;

    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!state.hasEstimate)
            Text(
              isThai
                  ? 'คิดเงินเมื่องานเสร็จตามเวลาจริง'
                  : 'Charged on completion (actual hours)',
              style: const TextStyle(
                  fontSize: 12, color: PgTokens.colorTextMuted),
            )
          else ...[
            _PriceRow(
              label: isThai
                  ? 'ค่าบริการรายชั่วโมง ($hours ชม.)'
                  : 'Hourly fee ($hours hrs)',
              value: Money.format(base),
            ),
            const SizedBox(height: PgTokens.space2),
            _PriceRow(
              label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Number of guards',
              value: '× $guards',
            ),
            if (tip > 0) ...[
              const SizedBox(height: PgTokens.space2),
              _PriceRow(
                label: isThai ? 'ทิป' : 'Tip',
                value: Money.format(tip),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
              child: Divider(height: 1, color: PgTokens.colorBorder),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(isThai ? 'รวมทั้งหมด' : 'Total',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: PgTokens.colorText)),
                ),
                Text(
                  Money.format(total),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13.5, color: PgTokens.colorTextMuted)),
        ),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText)),
      ],
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────────────────────

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? PgTokens.colorGreen800 : PgTokens.colorText;
    return Material(
      color: selected ? PgTokens.colorGreen50 : PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space3, vertical: PgTokens.space2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusFull),
            border: Border.all(
                color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ),
      ),
    );
  }
}

/// Icon for a place-type chip (no per-type icon key in the model — mapped here in the widget layer).
IconData _placeTypeIcon(String id) {
  switch (id) {
    case 'village':
      return Icons.home_outlined;
    case 'condo':
      return Icons.apartment;
    case 'factory':
      return Icons.factory_outlined;
    case 'event':
      return Icons.celebration_outlined;
    default:
      return Icons.more_horiz;
  }
}

/// ประเภทสถานที่ chip — icon over label box (the row at the top of the form, per design #66).
/// Selected = brand border + green-50 fill + green icon/text, matching [_PillChip]'s selected look.
class _PlaceTypeChip extends StatelessWidget {
  const _PlaceTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? PgTokens.colorGreen800 : PgTokens.colorText;
    return Material(
      color: selected ? PgTokens.colorGreen50 : PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(
              vertical: PgTokens.space3, horizontal: PgTokens.space2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            border: Border.all(
                color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: PgTokens.space2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space3, vertical: PgTokens.space2),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline,
              size: 15, color: PgTokens.colorWarning),
          const SizedBox(width: PgTokens.space2),
          Flexible(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorWarning)),
          ),
        ],
      ),
    );
  }
}
