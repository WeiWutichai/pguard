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
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? PgTokens.colorPrimary,
          foregroundColor: foreground,
          disabledBackgroundColor: PgTokens.colorBorder,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PgTokens.radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label),
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
