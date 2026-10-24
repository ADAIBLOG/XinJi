import 'package:flutter/material.dart';
import 'package:xinji/app/theme/app_tokens.dart';
import 'package:xinji/core/widgets/pressable.dart';

class GlassStyle {
  const GlassStyle._();

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color fill(BuildContext context) => _dark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.92);

  static Color edge(BuildContext context) => _dark(context)
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.black.withValues(alpha: 0.06);

  static List<BoxShadow> lift(BuildContext context) => _dark(context)
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ];
}

/// 玻璃质感圆形图标按钮（复刻 Streak GlassIconButton）。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: tooltip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: GlassStyle.fill(context),
            border: Border.all(color: GlassStyle.edge(context)),
            boxShadow: GlassStyle.lift(context),
          ),
          child: Icon(icon, size: size * 0.47, color: context.colors.onSurface),
        ),
      ),
    );
    final tip = tooltip;
    return tip == null ? button : Tooltip(message: tip, child: button);
  }
}

/// 玻璃质感胶囊按钮（复刻 Streak GlassPill）。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    required this.onTap,
    this.tint,
    this.height = 40,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color? tint;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: tint ?? GlassStyle.fill(context),
            border: Border.all(
              color: tint == null
                  ? GlassStyle.edge(context)
                  : Colors.white.withValues(alpha: 0.18),
            ),
            boxShadow: tint == null
                ? GlassStyle.lift(context)
                : [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );
  }
}
