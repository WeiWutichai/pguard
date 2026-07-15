import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A 6-box OTP entry (per design: 44×54 boxes, mono digits, focus/error rings). A single
/// transparent [TextField] captures input; the boxes render the digits. `onCompleted` fires
/// when all [length] digits are entered.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.error = false,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool error;
  final bool autofocus;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// The last text we reported, so a controller notification that didn't change the text (a cursor
  /// move) is ignored and a full code isn't fired twice for the same value.
  String _reported = '';

  @override
  void initState() {
    super.initState();
    // Drive completion from the CONTROLLER, not the TextField's `onChanged` callback. On a real
    // device the IME / SMS-autofill can write the value straight into the controller (the boxes
    // fill) WITHOUT invoking `onChanged` — so an onChanged-based trigger silently never fires and
    // the screen looks hung (staging 2026-07-15: 6 boxes filled, no verify, no error). A controller
    // listener fires on every value change regardless of the input path.
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final value = _controller.text;
    if (value == _reported) return; // selection-only change → nothing to do
    _reported = value;
    setState(() {});
    widget.onChanged?.call(value);
    // `>=` not `==`: a paste / SMS-autofill insert can land the whole code in one update.
    if (value.length >= widget.length) widget.onCompleted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) {
            final hasDigit = i < text.length;
            final isActive = i == text.length;
            final borderColor = widget.error
                ? PgTokens.colorDanger
                : (isActive
                    ? PgTokens.colorPrimary
                    : PgTokens.colorBorderStrong);
            return Container(
              width: 44,
              height: 54,
              // 3.0 (was 4.5): six 44px boxes + margins must fit a 360dp-wide screen inside the
              // screen padding — the wider gap overflowed by 6px on smaller phones (staging OPPO).
              margin: const EdgeInsets.symmetric(horizontal: 3.0),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PgTokens.colorSurface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: borderColor, width: 1.5),
                boxShadow: isActive && !widget.error
                    ? const [
                        BoxShadow(
                            color: PgTokens.colorFocusRing,
                            blurRadius: 0,
                            spreadRadius: 4)
                      ]
                    : null,
              ),
              child: Text(
                hasDigit ? text[i] : '',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  color: PgTokens.colorText,
                ),
              ),
            );
          }),
        ),
        // Transparent capture field on top of the boxes (taps focus it; OS keypad appears).
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              // Let the OS offer the incoming SMS code as a one-tap autofill chip (Android 8+ / iOS)
              // — the most reliable delivery path, sidestepping a dropped keystroke on the IME.
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: widget.length,
              showCursor: false,
              cursorColor: Colors.transparent,
              style: const TextStyle(color: Colors.transparent),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  counterText: '', border: InputBorder.none),
              // No `onChanged:` — completion is driven by the controller listener above, which also
              // catches autofill/IME writes that skip this callback.
              // The keyboard's action key is an invisible manual-submit fallback (no on-screen CTA,
              // per the design): if the boxes are full but auto-submit somehow didn't fire, the
              // Done/✓ key still triggers a verify. Ignored when the code is short.
              onSubmitted: (value) {
                if (value.length >= widget.length) {
                  widget.onCompleted?.call(value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
