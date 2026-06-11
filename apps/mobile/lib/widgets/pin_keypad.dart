import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// The 3×4 numeric keypad (1–9, optional biometric, 0, backspace). Pure presentation —
/// digit handling lives in the screen/controller. Disabled during lockout.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Design `.key`: fixed 56px tall keys with 8px gaps (not aspect-ratio derived).
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: PgTokens.space2,
        crossAxisSpacing: PgTokens.space2,
        mainAxisExtent: 56,
      ),
      children: [
        for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
          _digit(d),
        _biometricOrEmpty(),
        _digit('0'),
        _action(
          icon: Icons.backspace_outlined,
          onTap: enabled ? onBackspace : null,
          semantic: 'Delete',
        ),
      ],
    );
  }

  Widget _digit(String d) => _KeypadKey(
        onTap: enabled ? () => onDigit(d) : null,
        child: Text(
          d,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorText,
          ),
        ),
      );

  Widget _biometricOrEmpty() {
    if (onBiometric == null) return const SizedBox.shrink();
    return _action(
        icon: Icons.fingerprint,
        onTap: enabled ? onBiometric : null,
        semantic: 'Biometric unlock',
        filled: false);
  }

  Widget _action(
          {required IconData icon,
          VoidCallback? onTap,
          required String semantic,
          bool filled = false}) =>
      _KeypadKey(
        onTap: onTap,
        filled: filled,
        child: Icon(icon,
            size: 24, color: PgTokens.colorPrimary, semanticLabel: semantic),
      );
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({required this.child, this.onTap, this.filled = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? PgTokens.colorSunken : Colors.transparent,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Center(child: child),
      ),
    );
  }
}
