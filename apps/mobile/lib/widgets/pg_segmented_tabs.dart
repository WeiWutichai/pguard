import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// Design `.jtabs` / `.jtab`: an N-segment control. The active segment is a brand-green fill with
/// dark text; the rest are sunken pills with muted text. When [counts] is given, a non-zero count
/// is appended to its label (e.g. "เสร็จ 12"). Shared by the guard Jobs (②) and Work-history (⑦)
/// screens.
class PgSegmentedTabs extends StatelessWidget {
  const PgSegmentedTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.counts,
  });

  final List<String> labels;

  /// Optional per-segment counts; a count > 0 is appended to the label.
  final List<int>? counts;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Seg(
                label: (counts != null && counts![i] > 0)
                    ? '${labels[i]} ${counts![i]}'
                    : labels[i],
                active: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Design `.jtab.on` (light theme — the app is light-only): a deep green-900 fill with white
    // text. (The brand-int + dark-text variant in the mockup is `[data-theme="dark"]`-gated.)
    return Material(
      color: active ? PgTokens.colorGreen900 : PgTokens.colorSunken,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : PgTokens.colorTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}
