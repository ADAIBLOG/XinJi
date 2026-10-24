import 'package:flutter/material.dart';

/// 数字滚动 + 弹性缩放动画（复刻 Streak 的 AnimatedStatNumber）。
///
/// 首帧直接显示终值（不从 0 滚动）——打开页面时数字滚动会因
/// 文本宽度变化引起布局抖动；仅当数值后续变化时才平滑滚动。
class AnimatedStatNumber extends StatefulWidget {
  const AnimatedStatNumber({
    super.key,
    required this.value,
    required this.style,
    this.currency = '',
    this.decimals = 2,
  });

  final double value;
  final TextStyle style;
  final String currency;
  final int decimals;

  @override
  State<AnimatedStatNumber> createState() => _AnimatedStatNumberState();
}

class _AnimatedStatNumberState extends State<AnimatedStatNumber> {
  /// 动画起点锁定为首次值：首次 build 直接显示终值。
  late final double _initial = widget.value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: _initial, end: widget.value),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => FittedBox(
          // 超宽时自动缩小字号，保证数字完整显示（不再省略截断）
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            '${widget.currency}${_format(v)}',
            maxLines: 1,
            softWrap: false,
            style: widget.style.copyWith(
              fontFeatures: [
                ...widget.style.fontFeatures ?? const [],
                const FontFeature.tabularFigures(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 金额固定保留 [decimals] 位小数（尾零也保留，如 240.00）。
  String _format(double v) => v.toStringAsFixed(widget.decimals);
}
