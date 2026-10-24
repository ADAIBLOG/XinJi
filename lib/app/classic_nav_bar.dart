import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:xinji/app/theme/app_tokens.dart';

typedef ClassicNavItem = ({IconData icon, String label});

/// Streak 风格底部导航：激活项图标落在实心色块内。
/// [showLabels] 控制是否显示文字标签，[circleShape] 控制色块为圆形或圆角方块。
class ClassicNavBar extends StatefulWidget {
  const ClassicNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    this.showLabels = false,
    this.circleShape = false,
  });

  final List<ClassicNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool showLabels;
  final bool circleShape;

  @override
  State<ClassicNavBar> createState() => _ClassicNavBarState();
}

class _ClassicNavBarState extends State<ClassicNavBar>
    with TickerProviderStateMixin {
  static const _tall = 64.0;
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 30,
  );

  late final AnimationController _lens;
  late final AnimationController _press;

  /// 有文字标签时色块上下留白更小（容纳图标+文字），仅图标时更宽松。
  double get _pad => widget.showLabels ? 5.0 : 8.0;

  @override
  void initState() {
    super.initState();
    _lens = AnimationController.unbounded(
      vsync: this,
      value: widget.index.toDouble(),
    );
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(ClassicNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !_press.isForwardOrCompleted) {
      _glide(widget.index);
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    _press.dispose();
    super.dispose();
  }

  double get _slot =>
      ((_availableWidth - _pad * 2) / widget.items.length).clamp(52.0, 78.0);

  double get _availableWidth {
    final width = MediaQuery.sizeOf(context).width;
    return (width - 32).clamp(0.0, 430.0);
  }

  void _glide(int index) => _lens.animateWith(
    SpringSimulation(_spring, _lens.value, index.toDouble(), _lens.velocity),
  );

  double _at(Offset local) =>
      ((local.dx - _pad) / _slot - 0.5).clamp(0, widget.items.length - 1);

  void _hold(LongPressStartDetails details) {
    _press.forward();
    _lens.value = _at(details.localPosition);
  }

  void _drag(LongPressMoveUpdateDetails details) {
    _lens.value = _at(details.localPosition);
  }

  void _drop([LongPressEndDetails? _]) {
    _press.reverse();
    final target = _lens.value.round();
    _glide(target);
    if (target != widget.index) widget.onSelect(target);
  }

  void _tap(TapUpDetails details) {
    final target = _at(details.localPosition).round();
    _glide(target);
    if (target != widget.index) widget.onSelect(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = context.tokens.muted;
    final count = widget.items.length;

    return LayoutBuilder(
      builder: (context, box) {
        final full = ((box.maxWidth - _pad * 2) / count).clamp(52.0, 78.0);
        final width = full * count + _pad * 2;

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (tap) => tap.onTapUp = _tap,
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: const Duration(milliseconds: 220),
                  ),
                  (press) => press
                    ..onLongPressStart = _hold
                    ..onLongPressMoveUpdate = _drag
                    ..onLongPressEnd = _drop
                    ..onLongPressCancel = _drop,
                ),
          },
          child: Container(
            width: width,
            height: _tall,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(_tall / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            // border 用独立 DecoratedBox：避免 Container 的 border 收缩内容区
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_tall / 2),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.09)
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: AnimatedBuilder(
                animation: Listenable.merge([_lens, _press]),
                builder: (context, _) {
                  final press = Curves.easeOut.transform(_press.value);
                  // 快速滑动时色块水平拉伸、轻微压扁（squash & stretch）
                  final stretch = (_lens.velocity.abs() / 14).clamp(0.0, 0.28);
                  final base = _tall - _pad * 2;
                  // 胶囊形：横跨整个槽位（最初版本透镜样式）；方块：仅图标格大小
                  final blockWidth = widget.circleShape
                      ? full * (1 + stretch + 0.1 * press)
                      : base * (1 + stretch + 0.1 * press);
                  final blockHeight = base * (1 - stretch * 0.35 + 0.1 * press);
                  final centre = _pad + full * (_lens.value + 0.5);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Streak 风格：实心色块随弹簧滑动
                      Positioned(
                        left: centre - blockWidth / 2,
                        top: (_tall - blockHeight) / 2,
                        width: blockWidth,
                        height: blockHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: widget.circleShape
                                ? BorderRadius.circular(blockHeight / 2)
                                : BorderRadius.circular(16),
                            color: scheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(
                                  alpha: dark ? 0.45 : 0.32,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        left: _pad,
                        right: _pad,
                        child: Row(
                          children: [
                            for (final (i, item) in widget.items.indexed)
                              _Item(
                                item: item,
                                width: full,
                                near: (1 - (_lens.value - i).abs()).clamp(
                                  0.0,
                                  1.0,
                                ),
                                press: press,
                                selected: i == widget.index,
                                showLabel: widget.showLabels,
                                onTap: () {
                                  _glide(i);
                                  widget.onSelect(i);
                                },
                                active: scheme.onPrimary,
                                muted: muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.item,
    required this.width,
    required this.near,
    required this.press,
    required this.selected,
    required this.showLabel,
    required this.onTap,
    required this.active,
    required this.muted,
  });

  final ClassicNavItem item;
  final double width;
  final double near;
  final double press;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  final Color active;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    // 色块滑入时图标尽早过渡到色块前景色
    final t = Curves.easeOutCubic.transform(near.clamp(0.0, 1.0));
    final tint = Color.lerp(muted, active, t)!;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Center(
          child: showLabel
              ? Transform.scale(
                  scale: 1 + 0.1 * near * press,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, size: 20, color: tint),
                      const SizedBox(height: 3),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: TextStyle(
                                  fontFamily: 'Figtree',
                                  fontSize: 10.5,
                                  height: 1.1,
                                  fontWeight: near > 0.5
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: tint,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Transform.scale(
                  scale: 1 + 0.1 * near * press,
                  child: Icon(item.icon, size: 22, color: tint),
                ),
        ),
      ),
    );
  }
}
