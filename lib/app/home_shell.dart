import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:xinji/app/classic_nav_bar.dart';
import 'package:xinji/features/records/pages/today_page.dart';
import 'package:xinji/features/settings/pages/settings_page.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';
import 'package:xinji/features/statistics/pages/stats_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Tab { today, stats, settings }

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  _Tab _tab = _Tab.today;
  final _visited = <_Tab>{_Tab.today};

  late final AnimationController _swap;

  static const _tabs = [_Tab.today, _Tab.stats, _Tab.settings];

  @override
  void initState() {
    super.initState();
    _swap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
  }

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  void _select(_Tab tab) {
    if (tab == _tab) return;
    setState(() {
      _visited.add(tab);
      _tab = tab;
    });
    _swap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final navSettings = context.watch<SettingsController>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_tab != _Tab.today) {
            _select(_Tab.today);
          } else {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            _FadeSwap(
              animation: _swap,
              child: IndexedStack(
                index: _tabs.indexOf(_tab),
                children: [
                  for (final tab in _tabs)
                    TickerMode(
                      enabled: tab == _tab,
                      child: _visited.contains(tab)
                          ? _pageOf(tab)
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
              child: Center(
                child: ClassicNavBar(
                  items: [
                    for (final tab in _tabs)
                      (icon: _iconOf(tab), label: _labelOf(tab)),
                  ],
                  index: _tabs.indexOf(_tab),
                  onSelect: (i) => _select(_tabs[i]),
                  showLabels: navSettings.navBarLabels,
                  circleShape: navSettings.navBarCircle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _pageOf(_Tab tab) => switch (tab) {
  _Tab.today => const TodayPage(),
  _Tab.stats => const StatsPage(),
  _Tab.settings => const SettingsPage(),
};

IconData _iconOf(_Tab tab) => switch (tab) {
  _Tab.today => LucideIcons.house,
  _Tab.stats => LucideIcons.chartColumn,
  _Tab.settings => LucideIcons.settings,
};

String _labelOf(_Tab tab) => switch (tab) {
  _Tab.today => '今日',
  _Tab.stats => '统计',
  _Tab.settings => '设置',
};

/// 页面切换淡入。
class _FadeSwap extends StatelessWidget {
  const _FadeSwap({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: 0.4 + 0.6 * t,
          child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
        );
      },
      child: child,
    );
  }
}
