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

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted?.call(value);
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
              margin: const EdgeInsets.symmetric(horizontal: 4.5),
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
              maxLength: widget.length,
              showCursor: false,
              cursorColor: Colors.transparent,
              style: const TextStyle(color: Colors.transparent),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  counterText: '', border: InputBorder.none),
              onChanged: _onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
