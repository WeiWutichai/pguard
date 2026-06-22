import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/place_search_controller.dart';
import '../../../core/location/place_search_service.dart';
import '../../../core/providers.dart';

/// A place-name search box (OSM Nominatim, free): type a place → debounced search → a results
/// dropdown → tapping a result reports its [PlaceResult] (name + coordinate) via [onSelected].
/// Reusable foundation for the booking-form redesign (sits above/with the map picker).
///
/// Respects Nominatim's policy from the client: a 500 ms debounce + latest-query-only results
/// (see [PlaceSearchController]) — no per-keystroke firing. Best-effort: a failed request yields
/// an empty list (no error UI, no throw). Bilingual via [isThai].
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.onSelected,
    required this.isThai,
    this.controller,
    this.hintText,
  });

  /// Fired when the user taps a result — carries the place name + its coordinate.
  final ValueChanged<PlaceResult> onSelected;
  final bool isThai;

  /// Optional external text controller (e.g. to keep the address field in sync). When null the
  /// field owns its own.
  final TextEditingController? controller;
  final String? hintText;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  late final TextEditingController _text =
      widget.controller ?? TextEditingController();
  late final PlaceSearchController _search = PlaceSearchController(
    service: ref.read(placeSearchServiceProvider),
  );

  List<PlaceResult> _results = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search.results.listen((r) {
      if (mounted) setState(() => _results = r);
    });
    _search.loading.listen((l) {
      if (mounted) setState(() => _loading = l);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    // Only dispose the controller we created.
    if (widget.controller == null) _text.dispose();
    super.dispose();
  }

  void _select(PlaceResult result) {
    _text.value = TextEditingValue(
      text: result.displayName,
      selection: TextSelection.collapsed(offset: result.displayName.length),
    );
    setState(() => _results = const []); // collapse the dropdown
    FocusScope.of(context).unfocus();
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.hintText ??
        (widget.isThai ? 'ค้นหาสถานที่' : 'Search for a place');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _text,
          onChanged: _search.onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon:
                const Icon(Icons.search, size: 20, color: PgTokens.colorTextMuted),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (_text.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: widget.isThai ? 'ล้าง' : 'Clear',
                        onPressed: () {
                          _text.clear();
                          _search.onQueryChanged('');
                          setState(() => _results = const []);
                        },
                      )),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
            ),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: PgTokens.space1),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: PgTokens.colorSurface,
              borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              border: Border.all(color: PgTokens.colorBorder),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: PgTokens.colorBorder),
              itemBuilder: (context, i) {
                final r = _results[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined,
                      size: 18, color: PgTokens.colorPrimary),
                  title: Text(
                    r.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: PgTokens.colorText),
                  ),
                  onTap: () => _select(r),
                );
              },
            ),
          ),
      ],
    );
  }
}
