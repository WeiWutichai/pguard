import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The primary green CTA (Send OTP / Sign in / View details). Shows a spinner while [busy]
/// and disables itself when [onPressed] is null or busy.
class PgPrimaryButton extends StatelessWidget {
  const PgPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.color,
    this.foreground = Colors.white,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    // Design `.cta`: 16px padding ≈ 52px tall, radius 16 (→ radiusXl, the app's mapping
    // for the design's 16px corners), 16.5px w600 label.
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? PgTokens.colorPrimary,
          foregroundColor: foreground,
          disabledBackgroundColor: PgTokens.colorBorder,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
          ),
          // Explicit family: a button's ButtonStyle text style does NOT inherit the theme's
          // `fontFamily`, so name the brand Thai face here or the label falls back to the OS
          // default font (and renders as tofu where there is no Thai fallback).
          textStyle: const TextStyle(
              fontFamily: 'IBMPlexSansThai',
              fontSize: 16.5,
              fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            // Render the label at its natural design size (16.5 w600 from the ButtonStyle above).
            // A FittedBox/scaleDown used to wrap this so two CTAs could share a row, but in a
            // cramped slot it shrank the text to an illegible size (the reported "tiny button
            // text" on the completed booking's rate + receipt buttons). Callers that place two
            // CTAs side by side must instead give them enough width; a genuinely over-long label
            // ellipsizes rather than silently shrinking.
            : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// A borderless green text button for secondary actions (resend, switch flow).
class PgGhostButton extends StatelessWidget {
  const PgGhostButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: PgTokens.colorPrimary),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
