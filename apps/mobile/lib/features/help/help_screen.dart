import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/controllers/locale_controller.dart';
import '../../widgets/pguard_header.dart';

/// Best-effort external launch (dialer / mail app). Swallows failures so a missing handler never
/// throws into the widget tree.
Future<void> _launch(String uri) async {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return;
  try {
    await launchUrl(parsed);
  } catch (_) {
    // No handler (e.g. a tablet with no dialer) — nothing to do.
  }
}

/// System screen 9 (`Mobile - System.html`) — Help / FAQ. 100% static client-side content
/// (the design's 3 FAQ items + 3 contact rows, verbatim). The search box filters the in-memory
/// FAQ list (no backend search). Contact rows are INFORMATIONAL: there is no tel-launcher dep, no
/// admin-support chat channel, and no bug-report endpoint yet, so the rows display the (config)
/// support details without faking a working action. Support phone/hours are named constants —
/// operational config, not a data fetch.
const String _kSupportPhone = '02-123-4567';
const String _kSupportHoursTh = '24 ชม.';
const String _kSupportHoursEn = '24 hrs';

class _Faq {
  const _Faq({
    required this.icon,
    required this.qTh,
    required this.qEn,
    required this.aTh,
    required this.aEn,
  });
  final IconData icon;
  final String qTh;
  final String qEn;
  final String aTh;
  final String aEn;
}

const List<_Faq> _faqs = [
  _Faq(
    icon: Icons.info_outline,
    qTh: 'จองเจ้าหน้าที่อย่างไร?',
    qEn: 'How do I book a guard?',
    aTh:
        'เลือกบริการ → ปักหมุดตำแหน่ง → กดเรียกเจ้าหน้าที่ ระบบจะค้นหา รปภ. ใกล้คุณให้อัตโนมัติ',
    aEn:
        'Pick a service, drop a pin, tap request — we find nearby guards automatically.',
  ),
  _Faq(
    icon: Icons.payments_outlined,
    qTh: 'การชำระเงินและคืนเงิน',
    qEn: 'Payments & refunds',
    aTh: 'คิดเงินตามเวลาจริง คืนเงินส่วนต่างอัตโนมัติภายใน 3–5 วันทำการ',
    aEn:
        'Charged by actual time; the difference is auto-refunded within 3–5 business days.',
  ),
  _Faq(
    icon: Icons.shield_outlined,
    qTh: 'ความปลอดภัยและความเป็นส่วนตัว',
    qEn: 'Safety & privacy',
    aTh: 'เจ้าหน้าที่ทุกคนผ่านการตรวจประวัติและขึ้นทะเบียน รปภ.',
    aEn: 'Every guard is background-checked and a registered security officer.',
  ),
];

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  String _query = '';
  // First item open by default (design).
  final Set<int> _open = {0};

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final q = _query.trim().toLowerCase();
    final visible = <int>[
      for (var i = 0; i < _faqs.length; i++)
        if (q.isEmpty ||
            (isThai ? _faqs[i].qTh : _faqs[i].qEn).toLowerCase().contains(q) ||
            (isThai ? _faqs[i].aTh : _faqs[i].aEn).toLowerCase().contains(q))
          i,
    ];

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'ช่วยเหลือ' : 'Help',
        subtitle: isThai ? 'คำถามที่พบบ่อย · ติดต่อเรา' : 'FAQ & contact',
        showBack: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PgTokens.space4),
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: isThai ? 'ค้นหาคำถาม…' : 'Search…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: PgTokens.colorSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PgTokens.radiusMd),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: PgTokens.space4),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: PgTokens.space6),
                child: Text(
                  isThai ? 'ไม่พบคำถามที่ตรงกัน' : 'No matching questions',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: PgTokens.colorTextMuted),
                ),
              )
            else
              for (final i in visible)
                _FaqItem(
                  faq: _faqs[i],
                  isThai: isThai,
                  expanded: _open.contains(i),
                  onToggle: () => setState(
                      () => _open.contains(i) ? _open.remove(i) : _open.add(i)),
                ),
            const SizedBox(height: PgTokens.space5),
            Text(isThai ? 'ติดต่อเรา' : 'Contact us',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: PgTokens.space2),
            _ContactRow(
              icon: Icons.phone_outlined,
              title: isThai ? 'โทรหาฝ่ายสนับสนุน' : 'Call support',
              subtitle:
                  '$_kSupportPhone · ${isThai ? _kSupportHoursTh : _kSupportHoursEn}',
              onTap: () => _launch('tel:$_kSupportPhone'),
            ),
            // No dedicated admin-support conversation / bug-report endpoint yet — until those exist,
            // route both to the support line so no contact row is dead (the reported "none work").
            _ContactRow(
              icon: Icons.chat_bubble_outline,
              title: isThai ? 'แชตกับแอดมิน' : 'Chat with admin',
              onTap: () => _launch('tel:$_kSupportPhone'),
            ),
            _ContactRow(
              icon: Icons.help_outline,
              title: isThai
                  ? 'แจ้งปัญหา / ส่งความเห็น'
                  : 'Report a bug / feedback',
              onTap: () => _launch('tel:$_kSupportPhone'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({
    required this.faq,
    required this.isThai,
    required this.expanded,
    required this.onToggle,
  });

  final _Faq faq;
  final bool isThai;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: PgTokens.space2),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(PgTokens.space4),
              child: Row(
                children: [
                  Icon(faq.icon, size: 18, color: PgTokens.colorPrimary),
                  const SizedBox(width: PgTokens.space3),
                  Expanded(
                    child: Text(isThai ? faq.qTh : faq.qEn,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right,
                        color: PgTokens.colorTextFaint),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  PgTokens.space4, 0, PgTokens.space4, PgTokens.space4),
              child: Text(isThai ? faq.aTh : faq.aEn,
                  style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: PgTokens.colorTextMuted)),
            ),
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// Informational contact row (design `.support-row`). Non-tappable: there is no tel-launcher dep,
/// no admin-support conversation, and no bug-report endpoint yet — so the row shows the support
/// detail honestly without faking a working action. Wire `onTap` once a real channel exists.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PgTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PgTokens.space2),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: PgTokens.colorGreen50,
                borderRadius: BorderRadius.circular(PgTokens.radiusMd),
              ),
              child: Icon(icon, size: 19, color: PgTokens.colorPrimary),
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            fontSize: 12, color: PgTokens.colorTextMuted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
