import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A round call-action button (accept / reject / end / mute …). Plugin-free so it is widget-testable.
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color = PgTokens.colorSunken,
    this.foreground = Colors.white,
    this.size = 64,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color color;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

/// The in-call control bar: mute, speaker, optional camera-flip (video), and end.
class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.isThai,
    required this.muted,
    required this.speakerOn,
    required this.showCamera,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool isThai;
  final bool muted;
  final bool speakerOn;
  final bool showCamera;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CallRoundButton(
          icon: muted ? Icons.mic_off : Icons.mic,
          tooltip: muted
              ? (isThai ? 'เปิดไมค์' : 'Unmute')
              : (isThai ? 'ปิดไมค์' : 'Mute'),
          color: muted ? Colors.white24 : PgTokens.colorSunken,
          size: 56,
          onPressed: onToggleMute,
        ),
        const SizedBox(width: PgTokens.space3),
        CallRoundButton(
          icon: speakerOn ? Icons.volume_up : Icons.volume_down,
          tooltip: isThai ? 'ลำโพง' : 'Speaker',
          color: speakerOn ? Colors.white24 : PgTokens.colorSunken,
          size: 56,
          onPressed: onToggleSpeaker,
        ),
        if (showCamera) ...[
          const SizedBox(width: PgTokens.space3),
          CallRoundButton(
            icon: Icons.cameraswitch,
            tooltip: isThai ? 'สลับกล้อง' : 'Flip camera',
            size: 56,
            onPressed: onSwitchCamera,
          ),
        ],
        const SizedBox(width: PgTokens.space3),
        CallRoundButton(
          icon: Icons.call_end,
          tooltip: isThai ? 'วางสาย' : 'End',
          color: PgTokens.colorDanger,
          size: 56,
          onPressed: onEnd,
        ),
      ],
    );
  }
}
