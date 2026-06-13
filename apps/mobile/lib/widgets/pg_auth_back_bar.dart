import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// Transparent app bar for the auth flow's PUSHED screens (captcha · OTP · set-PIN).
///
/// The hi-fi `Mobile - Auth.html` screens have NO green top bar — each screen's title lives
/// in its body [AuthHead]. So instead of the brand-green [PGuardHeader] we use a bar that
/// blends into the page (background = `--bg`, no elevation/tint) and carries only a back
/// chevron, since these screens are pushed and need a way back. It also sets the dark
/// status-bar icons the light background needs (the green header used light icons).
///
/// Root auth screens (phone entry, returning-user unlock) have no back affordance, so they
/// use `appBar: null` wrapped in an `AnnotatedRegion<SystemUiOverlayStyle>` instead — a
/// zero-height bar would not annotate the status bar.
class PgAuthBackBar extends StatelessWidget implements PreferredSizeWidget {
  const PgAuthBackBar({super.key, this.onBack});

  /// Custom back handler; defaults to `Navigator.maybePop`. Used e.g. by the set-PIN screen
  /// to step back from the confirm entry to the first entry instead of popping the route.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: PgTokens.colorBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      leading: IconButton(
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        color: PgTokens.colorText,
        tooltip: 'Back',
      ),
    );
  }
}
