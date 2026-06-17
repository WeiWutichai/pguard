import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/geo.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'service_selection_screen.dart' show serviceIcon;
import 'widgets/map_picker.dart';

/// Step 2 — the booking form. Captures location (map picker → reverse-geocoded place name),
/// schedule, hours, and guard count, then `POST /v1/bookings`. The price shown here is an
/// ESTIMATE (`indicative rate × hours × guards`); the authoritative figure comes back on the
/// created booking. UI per `Mobile Hirer Booking.html` (classic/map-forward).
class BookingFormScreen extends ConsumerStatefulWidget {
  const BookingFormScreen({super.key});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  static const List<int> _hourPresets = [4, 6, 8, 12];

  late final TextEditingController _address = TextEditingController(
    text: ref.read(bookingFlowControllerProvider).address,
  );

  BookingFlowController get _ctrl =>
      ref.read(bookingFlowControllerProvider.notifier);

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _onLocationPicked(GeoPlace place) {
    _ctrl.setLocation(place);
    // Keep the editable address field in sync with the picked place name.
    _address.value = TextEditingValue(
      text: place.placeName,
      selection: TextSelection.collapsed(offset: place.placeName.length),
    );
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: ref.read(bookingFlowControllerProvider).scheduledAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 14, minute: 0),
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 14, minute: 0);
    _ctrl.setSchedule(
        DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  Future<void> _submit() async {
    final ok = await _ctrl.createBooking();
    if (ok && mounted) context.push('/book/guards');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(bookingFlowControllerProvider);
    final service = state.service;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(light: true, 
        title: isThai ? 'จองเจ้าหน้าที่' : 'Book a guard',
        subtitle: service != null
            ? (isThai ? service.labelTh : service.labelEn)
            : 'Booking',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PgTokens.space4),
                children: [
                  _ServiceChips(
                    selected: service,
                    onSelect: _ctrl.selectService,
                    isThai: isThai,
                  ),
                  const SizedBox(height: PgTokens.space4),
                  _Label(isThai ? 'สถานที่' : 'Location'),
                  const SizedBox(height: PgTokens.space2),
                  MapPicker(
                    initial: state.place,
                    onChanged: _onLocationPicked,
                  ),
                  const SizedBox(height: PgTokens.space2),
                  TextField(
                    controller: _address,
                    onChanged: _ctrl.setAddress,
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
                  const SizedBox(height: PgTokens.space4),
                  _Label(isThai ? 'วันและเวลา' : 'Date & time'),
                  const SizedBox(height: PgTokens.space2),
                  _ScheduleRow(when: state.scheduledAt, onTap: _pickSchedule),
                  const SizedBox(height: PgTokens.space4),
                  _Label(isThai ? 'ระยะเวลา' : 'Duration'),
                  const SizedBox(height: PgTokens.space2),
                  _HourChips(
                    presets: _hourPresets,
                    selected: state.hours,
                    onSelect: _ctrl.setHours,
                  ),
                  const SizedBox(height: PgTokens.space4),
                  _Label(isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards'),
                  const SizedBox(height: PgTokens.space2),
                  _Stepper(
                    value: state.guardCount,
                    min: 1,
                    max: 20,
                    unit: isThai ? 'คน' : 'guards',
                    onChanged: _ctrl.setGuardCount,
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: PgTokens.space3),
                    Text(state.error!,
                        style: const TextStyle(color: PgTokens.colorDanger)),
                  ],
                ],
              ),
            ),
            _PriceBar(
              state: state,
              isThai: isThai,
              onSubmit: state.busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorTextMuted),
      );
}

class _ServiceChips extends StatelessWidget {
  const _ServiceChips({
    required this.selected,
    required this.onSelect,
    required this.isThai,
  });

  final SecurityService? selected;
  final ValueChanged<SecurityService> onSelect;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: PgTokens.space2,
      runSpacing: PgTokens.space2,
      children: [
        for (final service in SecurityService.values)
          _Chip(
            label: isThai ? service.labelTh : service.labelEn,
            icon: serviceIcon(service),
            selected: service == selected,
            onTap: () => onSelect(service),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: PgTokens.space1),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.when, required this.onTap});

  final DateTime? when;
  final VoidCallback onTap;

  String _format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)} น.';
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
                  size: 18, color: PgTokens.colorPrimary),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Text(
                  when != null ? _format(when!) : 'เลือกวันและเวลา',
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

class _HourChips extends StatelessWidget {
  const _HourChips({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  final List<int> presets;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: PgTokens.space2,
      runSpacing: PgTokens.space2,
      children: [
        for (final h in presets)
          _Chip(
            label: '$h ชม.',
            selected: h == selected,
            onTap: () => onSelect(h),
          ),
      ],
    );
  }
}

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

class _PriceBar extends StatelessWidget {
  const _PriceBar({
    required this.state,
    required this.isThai,
    required this.onSubmit,
  });

  final BookingFlowState state;
  final bool isThai;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isThai ? 'ราคาประเมิน' : 'Est. price',
                          style: const TextStyle(
                              fontSize: 12, color: PgTokens.colorTextMuted)),
                      Text(
                        state.hasEstimate
                            ? '${Money.format(state.estimateHourlySatang)}/ชม. × ${state.hours} ชม. × ${state.guardCount}'
                            : (isThai ? 'คิดราคาตามจริง' : 'Priced on actuals'),
                        style: const TextStyle(
                            fontSize: 11, color: PgTokens.colorTextFaint),
                      ),
                    ],
                  ),
                ),
                Text(
                  state.hasEstimate
                      ? Money.format(state.estimateTotalSatang)
                      : '—',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: PgTokens.space3),
            PgPrimaryButton(
              label: isThai ? 'ค้นหาเจ้าหน้าที่' : 'Find guards',
              busy: state.busy,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
