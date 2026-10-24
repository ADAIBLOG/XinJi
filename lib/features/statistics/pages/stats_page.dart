import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/app/theme/app_tokens.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/core/utils/format.dart';
import 'package:xinji/core/widgets/animated_stat_number.dart';
import 'package:xinji/core/widgets/page_header.dart';
import 'package:xinji/core/widgets/pressable.dart';
import 'package:xinji/features/records/data/day_mark.dart';
import 'package:xinji/features/records/state/earnings.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';
import 'package:xinji/features/settings/widgets/job_chips.dart';

/// 最早的统计月份：打卡/标记/加班与提成中最早的一个月；无任何数据时为当月。
DateTime _earliestStatMonth(RecordsController records, {String? jobId}) {
  final now = DateTime.now();
  final current = DateTime(now.year, now.month);
  DateTime earliest = current;
  final data = records.earliestDataDate(jobId: jobId);
  if (data != null) {
    final m = DateTime(data.year, data.month);
    if (m.isBefore(earliest)) earliest = m;
  }
  for (final e in records.commissions.entries) {
    if (jobId != null && !e.value.containsKey(jobId)) continue;
    final parts = e.key.split('-');
    if (parts.length != 2) continue;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) continue;
    final month = DateTime(y, m);
    if (month.isBefore(earliest)) earliest = month;
  }
  return earliest;
}

/// 税后累计：(税后合计, 扣税合计)。税收关闭时为税前合计、0。
/// 设置了统计起始日期时，仅累计该日期至今的数据。
(double net, double tax) _netTotalOf(
  SettingsController settings,
  RecordsController records, {
  String? jobId,
}) {
  final now = DateTime.now();
  final start = settings.statsTotalStart;
  final firstMonth = start == null
      ? _earliestStatMonth(records, jobId: jobId)
      : DateTime(start.year, start.month);
  final r = netEarningsOfAnchorPeriod(
    settings,
    records,
    firstMonth,
    DateTime(now.year, now.month),
    anchorDate: start,
    jobId: jobId,
  );
  return (r.net, r.tax);
}

/// 锚点周期逐月税后合计（首月自 [anchorDate] 起算；null 时整月）。
/// 返回 (税后合计, 扣税合计)。各工作按自己的个税设置独立计税（不合并）。
({double net, double tax}) netEarningsOfAnchorPeriod(
  SettingsController settings,
  RecordsController records,
  DateTime firstMonth,
  DateTime lastMonth, {
  DateTime? anchorDate,
  String? jobId,
}) {
  var net = 0.0;
  var tax = 0.0;
  var m = DateTime(firstMonth.year, firstMonth.month);
  final end = DateTime(lastMonth.year, lastMonth.month);
  final jobs = jobId == null
      ? settings.jobs
      : [for (final j in settings.jobs) if (j.id == jobId) j];
  while (!m.isAfter(end)) {
    final monthEnd = DateTime(m.year, m.month + 1, 0);
    final first = anchorDate != null &&
            m.year == anchorDate.year &&
            m.month == anchorDate.month
        ? anchorDate
        : DateTime(m.year, m.month, 1);
    for (final job in jobs) {
      final gross =
          earningsOf(
            settings,
            records,
            start: first,
            end: monthEnd,
            jobId: job.id,
          ) +
          records.commissionOf(m, jobId: job.id);
      // 个税按月判定（开关关闭/当月未生效不计税）
      final t = taxEffectiveInMonth(job, m) ? taxOfJob(job, gross) : 0.0;
      net += gross - t;
      tax += t;
    }
    m = DateTime(m.year, m.month + 1);
  }
  return (net: net, tax: tax);
}

/// 本周周期起点：按设置的每周起始日（1=周一 … 7=周日）循环。
DateTime weekAnchorStartOf(DateTime now, int weekStart) {
  final day = DateTime(now.year, now.month, now.day);
  var diff = (day.weekday - weekStart) % 7;
  if (diff < 0) diff += 7;
  return day.subtract(Duration(days: diff));
}

/// 本月周期起点：按设置的每月循环起始日（短月自动按月末）。
DateTime monthAnchorStartOf(DateTime now, int anchorDay) {
  DateTime startOf(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      anchorDay > daysInMonth ? daysInMonth : anchorDay,
    );
  }

  final daysThisMonth = DateTime(now.year, now.month + 1, 0).day;
  final eff = anchorDay > daysThisMonth ? daysThisMonth : anchorDay;
  return now.day >= eff
      ? startOf(now.year, now.month)
      : startOf(now.year, now.month - 1);
}

/// 年度周期起点：按设置的年度循环起始（月、日）。
DateTime yearAnchorStartOf(DateTime now, int month, int day) {
  final anchorThisYear = DateTime(now.year, month, day);
  return now.isBefore(anchorThisYear)
      ? DateTime(now.year - 1, month, day)
      : anchorThisYear;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with WidgetsBindingObserver {
  /// 工作筛选：null = 全部工作求和。
  String? _jobFilter;

  /// 午夜定时器：日期变更后刷新「今天」定位与各周期统计。
  Timer? _midnightTimer;

  /// 上次渲染日期：切回前台时检测跨天（后台期间定时器冻结）。
  String _lastDayKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastDayKey = dayKeyOf(DateTime.now());
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用后台期间定时器冻结：切回前台时若已跨天立即刷新
    if (state == AppLifecycleState.resumed && mounted) {
      final today = dayKeyOf(DateTime.now());
      if (today != _lastDayKey) {
        _lastDayKey = today;
        setState(() {});
      }
    }
  }

  void _scheduleMidnightRefresh() {
    final now = DateTime.now();
    _midnightTimer = Timer(
      untilNextMidnight(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleMidnightRefresh();
      },
    );
  }

  /// 配置本周循环起始日。
  Future<void> _configWeekStart(
    BuildContext context,
    SettingsController settings,
  ) async {
    final names = ['一', '二', '三', '四', '五', '六', '日'];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每周循环起始日',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: sheetContext.colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '「本周」将从所选星期起循环统计',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sheetContext.tokens.muted,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < 7; i++)
                    _AnchorChip(
                      label: '周${names[i]}',
                      selected: settings.statsWeekStart == i + 1,
                      onTap: () => Navigator.pop(sheetContext, i + 1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await settings.setStatsWeekStart(picked);
  }

  /// 配置本月循环起始日（每月几号，短月按月末）。
  Future<void> _configMonthAnchor(
    BuildContext context,
    SettingsController settings,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每月循环起始日',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: sheetContext.colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '如发薪日为 15 号，「本月」= 15 日 ~ 下月 14 日',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sheetContext.tokens.muted,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in const [1, 5, 10, 15, 20, 25])
                    _AnchorChip(
                      label: '$d 号',
                      selected: settings.statsMonthAnchorDay == d,
                      onTap: () => Navigator.pop(sheetContext, d),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext, -1),
                child: const Text('自定义日期…'),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == -1) {
      if (!mounted) return;
      final date = await showDatePicker(
        context: this.context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        helpText: '选择含起始日的日期',
      );
      if (date != null) await settings.setStatsMonthAnchorDay(date.day);
      return;
    }
    await settings.setStatsMonthAnchorDay(picked);
  }

  /// 配置年度循环起始（月、日）。
  Future<void> _configYearAnchor(
    BuildContext context,
    SettingsController settings,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '选择年度起始日期（取月、日）',
    );
    if (picked != null) {
      await settings.setStatsYearAnchor(picked.month, picked.day);
    }
  }

  /// 配置累计起始日期（null = 全部数据）。
  Future<void> _configTotalStart(
    BuildContext context,
    SettingsController settings,
  ) async {
    final action = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '累计统计范围',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: sheetContext.colors.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AnchorChip(
                    label: '全部数据',
                    selected: settings.statsTotalStart == null,
                    onTap: () => Navigator.pop(sheetContext, 0),
                  ),
                  _AnchorChip(
                    label: '自定义起始日…',
                    selected: settings.statsTotalStart != null,
                    onTap: () => Navigator.pop(sheetContext, 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    if (action == 0) {
      await settings.setStatsTotalStart(null);
      return;
    }
    if (!mounted) return;
    final date = await showDatePicker(
      context: this.context,
      initialDate: settings.statsTotalStart ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: '累计统计起始日期',
    );
    if (date != null) await settings.setStatsTotalStart(date);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final records = context.watch<RecordsController>();
    // 删除工作后筛选可能失效：回退到全部
    if (_jobFilter != null && settings.jobById(_jobFilter!) == null) {
      _jobFilter = null;
    }

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 10,
          16,
          120,
        ),
        children: [
          // 大标题 + 操作按钮：跟随页面滚动
          PageHeader(
            title: '统计',
            actions: [
              IconButton(
                tooltip: '记提成',
                onPressed: () => _showCommissionSheet(
                  context,
                  settings,
                  records,
                  jobId: _jobFilter,
                ),
                icon: const Icon(LucideIcons.handCoins, size: 20),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const _StatsSectionsPage(),
                  ),
                ),
                icon: const Icon(LucideIcons.settings2, size: 20),
              ),
            ],
          ),
          // 多工作时：顶部筛选全部 / 各工作
          if (settings.jobs.length > 1) ...[
            JobChips(
              jobs: settings.jobs,
              selectedJobId: _jobFilter,
              onSelect: (id) => setState(() => _jobFilter = id),
              showAll: true,
            ),
            const SizedBox(height: 16),
          ],
          ..._buildSections(context, settings, records),
        ],
      ),
    );
  }

  /// 按用户配置（顺序 + 显示与否）构建统计组件列表。
  List<Widget> _buildSections(
    BuildContext context,
    SettingsController settings,
    RecordsController records,
  ) {
    final jobId = _jobFilter;
    final now = DateTime.now();
    final monthStart = monthAnchorStartOf(now, settings.statsMonthAnchorDay);
    final yearStart = yearAnchorStartOf(
      now,
      settings.statsYearAnchorMonth,
      settings.statsYearAnchorDay,
    );
    final sections = settings.visibleStatsSections;
    if (sections.isEmpty) {
      final muted = context.tokens.muted;
      return [
        SizedBox(
          height: 320,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.settings2,
                  size: 34,
                  color: muted.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  '所有组件均已隐藏',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点击右上角按钮自定义统计页',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      for (final (i, section) in sections.indexed) ...[
        if (i > 0) const SizedBox(height: 16),
        switch (section) {
          StatsSection.total => _TotalCard(
            netTotal: _netTotalOf(settings, records, jobId: jobId),
            hours: settings.statsTotalStart == null
                ? records.hoursAll(jobId: jobId)
                : records.hoursBetween(settings.statsTotalStart!, now, jobId: jobId),
            days: daysOf(
              settings,
              records,
              start: settings.statsTotalStart,
              end: settings.statsTotalStart == null ? null : now,
              jobId: jobId,
            ),
            currency: settings.currency,
            taxEnabled: jobId == null
                ? settings.jobs.any((j) => j.taxEnabled)
                : (settings.jobById(jobId)?.taxEnabled ?? false),
            anchorText: settings.statsTotalStart == null
                ? null
                : '自 ${settings.statsTotalStart!.year}年'
                      '${settings.statsTotalStart!.month}月'
                      '${settings.statsTotalStart!.day}日起统计',
            onConfigure: () => _configTotalStart(context, settings),
          ),
          StatsSection.periods => Row(
            children: [
              Expanded(
                child: _PeriodCard(
                  label: '本周',
                  value: earningsOf(
                    settings,
                    records,
                    start: weekAnchorStartOf(now, settings.statsWeekStart),
                    end: now,
                    jobId: jobId,
                  ),
                  currency: settings.currency,
                  subLabel: settings.statsWeekStart == 1
                      ? null
                      : '每周${_weekdayName(settings.statsWeekStart)}起',
                  onTap: () => _configWeekStart(context, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PeriodCard(
                  label: '本月',
                  value: netEarningsOfAnchorPeriod(
                    settings,
                    records,
                    DateTime(monthStart.year, monthStart.month),
                    DateTime(now.year, now.month),
                    anchorDate: monthStart,
                    jobId: jobId,
                  ).net,
                  currency: settings.currency,
                  subLabel: settings.statsMonthAnchorDay == 1
                      ? null
                      : '每月${settings.statsMonthAnchorDay}日起',
                  onTap: () => _configMonthAnchor(context, settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PeriodCard(
                  label: '今年',
                  value: netEarningsOfAnchorPeriod(
                    settings,
                    records,
                    DateTime(yearStart.year, yearStart.month),
                    DateTime(now.year, now.month),
                    anchorDate: yearStart,
                    jobId: jobId,
                  ).net,
                  currency: settings.currency,
                  subLabel: settings.statsYearAnchorMonth == 1 &&
                          settings.statsYearAnchorDay == 1
                      ? null
                      : '每年${settings.statsYearAnchorMonth}月'
                            '${settings.statsYearAnchorDay}日起',
                  onTap: () => _configYearAnchor(context, settings),
                ),
              ),
            ],
          ),
          StatsSection.daily => _DailyChart(
            settings: settings,
            records: records,
            currency: settings.currency,
            jobId: jobId,
          ),
          StatsSection.calendar => _CalendarChart(
            settings: settings,
            records: records,
            currency: settings.currency,
            jobId: jobId,
          ),
          StatsSection.monthly => _MonthlyChart(
            settings: settings,
            records: records,
            currency: settings.currency,
            jobId: jobId,
          ),
        },
      ],
    ];
  }
}

/// 统计组件显示名称。
String _statsSectionLabel(StatsSection section) => switch (section) {
  StatsSection.total => '累计收入',
  StatsSection.periods => '本周 · 本月 · 今年',
  StatsSection.daily => '本周每日收入',
  StatsSection.calendar => '月历',
  StatsSection.monthly => '近 6 个月收入',
};

/// 统计组件图标。
IconData _statsSectionIcon(StatsSection section) => switch (section) {
  StatsSection.total => LucideIcons.wallet,
  StatsSection.periods => LucideIcons.calendarRange,
  StatsSection.daily => LucideIcons.barChart3,
  StatsSection.calendar => LucideIcons.calendarDays,
  StatsSection.monthly => LucideIcons.trendingUp,
};

/// 统计页组件自定义：长按拖动排序，开关控制是否显示。
class _StatsSectionsPage extends StatelessWidget {
  const _StatsSectionsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final order = settings.statsOrder;

    return Scaffold(
      appBar: AppBar(title: Text('自定义统计页')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '拖动调整组件顺序，开关控制是否显示。',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          Card(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: order.length,
              // onReorderItem 收到的 newIndex 已按移除项自动调整
              onReorderItem: (oldIndex, newIndex) {
                final next = [...order];
                next.insert(newIndex, next.removeAt(oldIndex));
                settings.setStatsOrder(next);
              },
              itemBuilder: (context, index) {
                final section = order[index];
                final visible = settings.statsSectionVisible(section);
                return Padding(
                  key: ValueKey(section),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.gripVertical,
                        size: 18,
                        color: muted.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        _statsSectionIcon(section),
                        size: 18,
                        color: visible
                            ? scheme.primary
                            : muted.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statsSectionLabel(section),
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: visible
                                ? scheme.onSurface
                                : muted.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      Switch(
                        value: visible,
                        onChanged: (v) =>
                            settings.setStatsSectionVisible(section, v),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.netTotal,
    required this.hours,
    required this.days,
    required this.currency,
    required this.taxEnabled,
    this.anchorText,
    this.onConfigure,
  });

  /// (税后合计, 扣税合计)；税收关闭时为 (税前合计, 0)。
  final (double, double) netTotal;
  final double hours;
  final double days;
  final String currency;
  final bool taxEnabled;

  /// 累计起始日期提示（null = 全部数据）。
  final String? anchorText;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final (net, tax) = netTotal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  taxEnabled ? '累计到手' : '累计收入',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const Spacer(),
                if (anchorText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      anchorText!,
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onConfigure,
                  child: Icon(
                    LucideIcons.calendarRange,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedStatNumber(
              value: net,
              currency: currency,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 42,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -1.4,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '累计工时 ${formatHours(hours)} · 出勤 ${formatQuantity(days)} 天',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            if (taxEnabled && tax > 0) ...[
              const SizedBox(height: 4),
              Text(
                '税前 $currency${formatMoney(net + tax)} · 已扣税 $currency${formatMoney(tax)}',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.label,
    required this.value,
    required this.currency,
    this.subLabel,
    this.onTap,
  });

  final String label;
  final double value;
  final String currency;

  /// 锚点提示（如「每周一起」「每月15日起」），null = 默认周期。
  final String? subLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedStatNumber(
                value: value,
                currency: currency,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: scheme.primary,
                ),
              ),
              if (subLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  subLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 周期锚点选项 chip。
class _AnchorChip extends StatelessWidget {
  const _AnchorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? scheme.primary : muted,
          ),
        ),
      ),
    );
  }
}

/// 星期名称（1=周一 … 7=周日）。
String _weekdayName(int weekday) => switch (weekday) {
  1 => '一',
  2 => '二',
  3 => '三',
  4 => '四',
  5 => '五',
  6 => '六',
  _ => '日',
};

/// 近 7 天每日收入柱状图。
class _DailyChart extends StatelessWidget {
  const _DailyChart({
    required this.settings,
    required this.records,
    required this.currency,
    this.jobId,
  });

  final SettingsController settings;
  final RecordsController records;
  final String currency;

  /// 工作筛选：null = 全部。
  final String? jobId;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 全部模式：当日各工作收入按标识色堆叠为柱段（金额 > 0 的工作）。
  List<BarChartRodStackItem> _dayJobParts(DateTime day) {
    final items = <BarChartRodStackItem>[];
    var from = 0.0;
    for (final job in settings.jobs) {
      final v = earningsOf(
        settings,
        records,
        start: day,
        end: day,
        jobId: job.id,
      );
      if (v > 0) {
        items.add(BarChartRodStackItem(from, from + v, job.color));
        from += v;
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final now = DateTime.now();
    final start = weekAnchorStartOf(now, settings.statsWeekStart);

    final bars = <BarChartGroupData>[];
    final values = <double>[];
    double maxVal = 0;
    // 全部模式：每天柱子按工作标识色堆叠。
    final stack = jobId == null && settings.jobs.length > 1;
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final value = earningsOf(
        settings,
        records,
        start: day,
        end: day,
        jobId: jobId,
      );
      values.add(value);
      if (value > maxVal) maxVal = value;
      final isToday = isSameDay(day, now);
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            if (stack)
              BarChartRodData(
                toY: value,
                width: 22,
                borderRadius: BorderRadius.circular(6),
                rodStackItems: _dayJobParts(day),
              )
            else
              BarChartRodData(
                toY: value,
                width: 22,
                borderRadius: BorderRadius.circular(6),
                color: isToday
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.32),
              ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本周每日收入',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.12 == 0 ? 10 : maxVal * 1.12,
                  barGroups: bars,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 15,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i > 6) return const SizedBox.shrink();
                          final v = values[i];
                          if (v <= 0) return const SizedBox.shrink();
                          final isToday = isSameDay(
                            start.add(Duration(days: i)),
                            now,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              formatMoney(v),
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 9.5,
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isToday ? scheme.primary : muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i > 6) return const SizedBox.shrink();
                          final day = start.add(Duration(days: i));
                          final isToday = isSameDay(day, now);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              isToday ? '今天' : _weekdays[i],
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isToday ? scheme.primary : muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, idx, rod, i) => BarTooltipItem(
                        '$currency${rod.toY.toStringAsFixed(rod.toY == rod.toY.roundToDouble() ? 0 : 2)}',
                        TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月历统计图（streak 风格）：状态颜色作为单元格背景填充。
/// 打卡日浅主题色底 + 当日薪资；休息日休息色实底 + 黑字；今天描边。
/// [jobId] 为工作筛选：null = 全部工作聚合展示。
class _CalendarChart extends StatefulWidget {
  const _CalendarChart({
    required this.settings,
    required this.records,
    required this.currency,
    this.jobId,
  });

  final SettingsController settings;
  final RecordsController records;
  final String currency;

  /// 工作筛选：null = 全部。
  final String? jobId;

  @override
  State<_CalendarChart> createState() => _CalendarChartState();
}

class _CalendarChartState extends State<_CalendarChart>
    with WidgetsBindingObserver {
  late DateTime _month;

  /// 午夜定时器：日期/月份变更后跟随刷新「今天」定位。
  Timer? _midnightTimer;

  /// 上次渲染日期：切回前台时检测跨天（后台期间定时器冻结）。
  String _lastDayKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _lastDayKey = dayKeyOf(now);
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用后台期间定时器冻结：切回前台时若已跨天立即刷新
    if (state == AppLifecycleState.resumed && mounted) {
      final now = DateTime.now();
      final today = dayKeyOf(now);
      if (today != _lastDayKey) {
        _lastDayKey = today;
        if (now.day == 1) {
          // 跨月：停留在刚结束的月份时自动跟随到新月份
          final prevMonth = DateTime(now.year, now.month, 0);
          if (_month.year == prevMonth.year &&
              _month.month == prevMonth.month) {
            _month = DateTime(now.year, now.month);
          }
        }
        setState(() {});
      }
    }
  }

  void _scheduleMidnightRefresh() {
    final now = DateTime.now();
    _midnightTimer = Timer(
      untilNextMidnight(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        final now = DateTime.now();
        // 跨月午夜：停留在刚结束的月份时自动跟随到新月份
        if (now.day == 1) {
          final prevMonth = DateTime(now.year, now.month, 0);
          if (_month.year == prevMonth.year &&
              _month.month == prevMonth.month) {
            _month = DateTime(now.year, now.month);
          }
        }
        setState(() {});
        _scheduleMidnightRefresh();
      },
    );
  }

  void _shift(int delta) {
    final now = DateTime.now();
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.tokens.muted;
    final now = DateTime.now();
    final isCurrentMonth = _month.year == now.year && _month.month == now.month;

    final firstDay = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final startOffset = firstDay.weekday - 1; // 周一为一周起点
    final rows = (startOffset + daysInMonth + 6) ~/ 7;
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);

    final monthTotal = netEarningsOfMonth(
      widget.settings,
      widget.records,
      _month,
      jobId: widget.jobId,
    );
    final monthDays = daysOf(
      widget.settings,
      widget.records,
      start: firstDay,
      end: monthEnd,
      jobId: widget.jobId,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_month.year}年${_month.month}月 日历'
                    '${widget.jobId == null ? '' : ' · ${widget.settings.jobById(widget.jobId!)?.name ?? ''}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ),
                _MetricToggle(settings: widget.settings),
                const SizedBox(width: 6),
                _MonthArrow(
                  icon: LucideIcons.chevronLeft,
                  onTap: () => _shift(-1),
                ),
                const SizedBox(width: 6),
                _MonthArrow(
                  icon: LucideIcons.chevronRight,
                  onTap: isCurrentMonth ? null : () => _shift(1),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // 星期表头
            Row(
              children: [
                for (final w in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: muted.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // 日期网格（streak 风格正方形格子）
            Column(
              children: [
                for (var r = 0; r < rows; r++)
                  Row(
                    children: [
                      for (var c = 0; c < 7; c++)
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _buildCell(
                              r * 7 + c - startOffset + 1,
                              daysInMonth,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '本月收入 ${widget.currency}${formatMoney(monthTotal)} · 出勤 ${formatQuantity(monthDays)} 天',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 某日总加班工时（手动 + 自动）。
  /// [jobId] 为空表示全部工作：手动加班全部计入，
  /// 自动加班只计当日「自动加班」开关生效的工作（分段口径按日取值）。
  double _totalOvertimeOf(String key, {String? jobId}) {
    final records = widget.records;
    final day = DateTime.tryParse(key) ?? DateTime.now();
    double autoOf(Job j) => j.effectiveAutoOvertime(day)
        ? records.autoOvertimeOf(key, j.standardWorkMinutes, jobId: j.id)
        : 0.0;
    final autoTotal = jobId != null
        ? (() {
            final job = widget.settings.jobById(jobId);
            return job == null ? 0.0 : autoOf(job);
          })()
        : widget.settings.jobs.fold<double>(0, (sum, j) => sum + autoOf(j));
    return records.overtimeOf(key, jobId: jobId) + autoTotal;
  }

  /// 休息色撞色避让：休息色与主题色相近（如主题选绿色系时与默认
  /// 清新绿撞色）导致休息日与工作日难区分，自动改用休息色板中
  /// 与主题色差异最大的颜色；不撞色时保持用户所选休息色不变。
  Color _restColorDistinct() {
    final rest = widget.settings.restColor;
    final accent = widget.settings.accent;
    int dist2(Color a, Color b) {
      final dr = ((a.r - b.r) * 255).round();
      final dg = ((a.g - b.g) * 255).round();
      final db = ((a.b - b.b) * 255).round();
      return dr * dr + dg * dg + db * db;
    }
    // RGB 距离 60 以内视为相近（撞色）
    if (dist2(rest, accent) > 3600) return rest;
    Color best = AppPalette.restColors.first;
    var bestDist = -1;
    for (final c in AppPalette.restColors) {
      final d = dist2(c, accent);
      if (d > bestDist) {
        bestDist = d;
        best = c;
      }
    }
    return best;
  }

  /// 单元格状态：背景色 / 数字色 / 小字色 / 小字内容。
  ({Color? bg, Color numberColor, Color subColor, String subText}) _dayState(
    DateTime day,
  ) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final now = DateTime.now();
    final jobId = widget.jobId;
    final job = jobId == null ? null : widget.settings.jobById(jobId);

    final key = dayKeyOf(day);
    final isFuture = day.isAfter(DateTime(now.year, now.month, now.day));
    final mark = jobId != null
        ? widget.records.markOf(key, jobId: jobId)
        : null;
    final punched = widget.records.hasPunchedOn(key, jobId: jobId);
    final isWork =
        punched ||
        (jobId != null
            ? (mark?.isWork ?? false)
            : widget.records.anyMark(key, (m) => m.isWork));
    final isLeave = jobId != null
        ? (mark?.isLeave ?? false)
        : widget.records.anyMark(key, (m) => m.isLeave);
    final isRestMark = jobId != null
        ? (mark?.isRest ?? false)
        : widget.records.anyMark(key, (m) => m.isRest);
    final totalOt = _totalOvertimeOf(key, jobId: jobId);
    final otText = totalOt > 0 ? '+${formatQuantity(totalOt)}h' : '';

    // streak 风格：状态颜色作为背景填充，文字黑色。
    Color? bg;
    Color numberColor;
    Color subColor = muted;
    String subText = '';

    if (isWork) {
      // 打卡/标记工作日：主题色浅底 + 工时或当日薪资；
      // 当日有加班（手动或自动）时用更深的底色突出。
      final otIndex = widget.settings.overtimeColorIndex;
      if (totalOt > 0 && otIndex >= 0) {
        bg = AppPalette.overtimeColors[otIndex];
        numberColor = Colors.black.withValues(alpha: 0.87);
        subColor = Colors.black.withValues(alpha: 0.66);
      } else {
        bg = scheme.primary.withValues(
          alpha: totalOt > 0 ? 0.75 : 0.32,
        );
        numberColor = scheme.onSurface;
        // 金额/工时小字用黑色（深色模式用近白保证可读）
        subColor = scheme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.66);
      }
      if (widget.settings.calendarShowsHours) {
        final hours = widget.records.dayHoursOf(key, jobId: jobId);
        final allHourly = jobId != null
            ? job?.calcMode == CalcMode.hourly
            : widget.settings.jobs.every((j) => j.calcMode == CalcMode.hourly);
        if (hours > 0) {
          subText = '${formatQuantity(hours)}h';
        } else if (allHourly) {
          // 时薪按工时计薪：无工时（打卡未闭合等）不显示天数
          subText = '0h';
        } else if (job != null) {
          // 固定薪资：按标准工时判断整天/半天（跨天分摊后可能为 0.5 天）
          final units = widget.records.dayUnitsOf(
            key,
            job.standardWorkMinutes,
            jobId: jobId,
          );
          subText = units >= 1 ? '1天' : '0.5天';
        } else {
          subText = '1天';
        }
      } else {
        // 金额只显示整数（四舍五入），保持格子简洁
        subText =
            '${widget.currency}${earningsOf(widget.settings, widget.records, start: day, end: day, jobId: jobId).round()}';
      }
    } else if (isLeave) {
      // 请假：请假色实底
      bg = widget.settings.leaveColor;
      numberColor = Colors.black.withValues(alpha: 0.87);
      subColor = Colors.black.withValues(alpha: 0.66);
      subText = otText.isNotEmpty ? otText : '假';
    } else if (isRestMark) {
      // 手工标记休息日：休息色实底（与主题色撞色时自动避让）
      bg = _restColorDistinct();
      numberColor = Colors.black.withValues(alpha: 0.87);
      subColor = Colors.black.withValues(alpha: 0.66);
      subText = otText.isNotEmpty ? otText : '休';
    } else {
      // 首次使用前（早于最早记录日或尚无任何数据）：无状态置灰，
      // 不按排班推算、也不算缺勤。
      final earliest = widget.records.earliestDataDate(jobId: jobId);
      final beforeFirstUse =
          earliest == null ||
          day.isBefore(DateTime(earliest.year, earliest.month, earliest.day));
      final scheduledRest = jobId != null
          ? (job?.isScheduledRest(day) ?? false)
          : widget.settings.isScheduledRestAll(day);
      if (isFuture || beforeFirstUse) {
        numberColor = muted.withValues(alpha: 0.4);
      } else if (scheduledRest) {
        // 排班休息日：休息色实底（与主题色撞色时自动避让）
        bg = _restColorDistinct();
        numberColor = Colors.black.withValues(alpha: 0.87);
        subColor = Colors.black.withValues(alpha: 0.66);
        subText = otText.isNotEmpty ? otText : '休';
      } else if (isSameDay(day, now)) {
        // 今天尚未打卡：不算缺勤，无状态置灰（打过卡即实时更新）
        numberColor = muted.withValues(alpha: 0.4);
      } else {
        // 过去未打卡且非排班休息：缺勤红
        bg = AppPalette.absentColor;
        numberColor = Colors.black.withValues(alpha: 0.87);
        subColor = Colors.black.withValues(alpha: 0.66);
        subText = otText.isNotEmpty ? otText : '缺';
      }
    }
    return (
      bg: bg,
      numberColor: numberColor,
      subColor: subColor,
      subText: subText,
    );
  }

  Widget _buildCell(int dayNum, int daysInMonth) {
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox.expand();
    }
    final scheme = context.colors;
    final now = DateTime.now();

    final day = DateTime(_month.year, _month.month, dayNum);
    final isToday = isSameDay(day, now);
    final state = _dayState(day);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onDayTapped(day),
      onLongPress: () => _onDayLongPressed(day),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: state.bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: scheme.primary, width: 1.8)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNum',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: state.numberColor,
              ),
            ),
            const SizedBox(height: 3),
            // 金额等长文本完整显示：超出格子宽度时等比缩小字号，不截断
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  state.subText,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: state.subColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 全部模式明细行：该工作当日状态文本（打卡收入/标记/排班/未打卡）。
  String _jobDayStatus(
    SettingsController settings,
    RecordsController records,
    String key,
    DateTime day,
    Job job,
  ) {
    final ot = _totalOvertimeOf(key, jobId: job.id);
    final otSuffix = ot > 0 ? ' · +${formatQuantity(ot)}h' : '';
    if (records.hasPunchedOn(key, jobId: job.id)) {
      final earn = earningsOf(
        settings,
        records,
        start: day,
        end: day,
        jobId: job.id,
      );
      final hours = records.dayHoursOf(key, jobId: job.id);
      return '${widget.currency}${formatMoney(earn)} · ${formatQuantity(hours)}h$otSuffix';
    }
    final mark = records.markOf(key, jobId: job.id);
    if (mark != null) {
      if (mark.isRest) return '休息$otSuffix';
      if (mark.isLeave) return '请假$otSuffix';
      if (mark.isWork) return '已标记$otSuffix';
    }
    if (job.isScheduledRest(day)) return '排班休息$otSuffix';
    return '未打卡';
  }

  /// 短按日期：查看当日打卡记录与各工作明细（长按进入编辑）。
  /// 未来日期无数据可查，不响应。
  Future<void> _onDayTapped(DateTime day) async {
    final now = DateTime.now();
    if (day.isAfter(DateTime(now.year, now.month, now.day))) return;
    final settings = widget.settings;
    final records = widget.records;
    if (settings.jobs.isEmpty) return;
    final key = dayKeyOf(day);
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1];
    final jobId = widget.jobId;
    final multiJob = jobId == null && settings.jobs.length > 1;

    String fmtTime(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    // 跨天上班卡：显示「昨日 HH:mm」或「M/d HH:mm」
    String fmtCarry(DateTime t) {
      final yesterday = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
      if (isSameDay(t, yesterday)) return '昨日 ${fmtTime(t)}';
      return '${t.month}/${t.day} ${fmtTime(t)}';
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final scheme = sheetContext.colors;
        final muted = sheetContext.tokens.muted;
        final carry = records.carryOverIn(key, jobId: jobId);
        final punches = records.punchesOf(key, jobId: jobId);
        final display = [?carry, ...punches];
        final hours = records.dayHoursOf(key, jobId: jobId);
        final earn = earningsOf(
          settings,
          records,
          start: day,
          end: day,
          jobId: jobId,
        );
        final ot = _totalOvertimeOf(key, jobId: jobId);
        // 当日明细：基本工时（不含加班）、加班拆分、个税（月度口径）
        final base = records.baseHoursOf(key, jobId: jobId);
        final manualOt = records.overtimeOf(key, jobId: jobId);
        final autoOt = ot - manualOt;
        final tax = taxOfMonth(
          settings,
          records,
          DateTime(day.year, day.month),
          jobId: jobId,
        );

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${day.month}月${day.day}日 · 周$weekday',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '合计 ${widget.currency}${formatMoney(earn)} · '
                    '${formatQuantity(hours)} 小时'
                    '${ot > 0 ? ' · 加班 ${formatQuantity(ot)}h' : ''}',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 当日数据：基本工时 / 加班拆分 / 当日收入 / 本月个税
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _DayStat(
                                  label: '基本工时',
                                  value: base > 0
                                      ? '${formatQuantity(base)} 小时'
                                      : '无',
                                ),
                              ),
                              Expanded(
                                child: _DayStat(
                                  label: '加班工时',
                                  value: ot > 0
                                      ? '${formatQuantity(ot)} 小时'
                                      : '无',
                                  sub: ot > 0
                                      ? [
                                          if (manualOt > 0)
                                            '手动 ${formatQuantity(manualOt)}',
                                          if (autoOt > 0)
                                            '自动 ${formatQuantity(autoOt)}',
                                        ].join(' · ')
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _DayStat(
                                  label: '当日收入（税前）',
                                  value:
                                      '${widget.currency}${formatMoney(earn)}',
                                ),
                              ),
                              Expanded(
                                child: _DayStat(
                                  label: '本月个税',
                                  value: tax > 0
                                      ? '-${widget.currency}${formatMoney(tax)}'
                                      : '未开启',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (multiJob) ...[
                    const SizedBox(height: 12),
                    for (final j in settings.jobs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _DayJobRow(
                          job: j,
                          selected: false,
                          status: _jobDayStatus(settings, records, key, day, j),
                          onTap: () {},
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  if (display.isNotEmpty) ...[
                    Text(
                      '打卡记录',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final (i, p) in display.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              p.isIn
                                  ? LucideIcons.logIn
                                  : LucideIcons.logOut,
                              size: 15,
                              color: p.isIn
                                  ? scheme.primary
                                  : muted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              i == 0 && carry != null
                                  ? fmtCarry(p.time)
                                  : fmtTime(p.time),
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 13,
                                fontWeight: i == 0 && carry != null
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: i == 0 && carry != null
                                    ? muted
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              p.isIn ? '上班' : '下班',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else
                    Text(
                      '当天无打卡记录',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      '长按日历日期可编辑标记与加班',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 长按日期：手动标记工作日/休息日/请假、记加班（忘打卡补记等）。
  /// 全部模式下弹层先展示各工作明细行（行即选择器，点选后编辑该工作）；
  /// 单工作/筛选模式直接进入编辑。
  /// 未来日期不可编辑（尚未到来的日子）；今天与历史日期可编辑。
  Future<void> _onDayLongPressed(DateTime day) async {
    final now = DateTime.now();
    if (day.isAfter(DateTime(now.year, now.month, now.day))) return;
    final settings = widget.settings;
    final records = widget.records;
    if (settings.jobs.isEmpty) return;
    final key = dayKeyOf(day);
    final multiJob = widget.jobId == null && settings.jobs.length > 1;
    var selJobId =
        widget.jobId ?? settings.activeJobId ?? settings.jobs.first.id;
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1];

    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final job = settings.jobById(selJobId);
          final mark = records.markOf(key, jobId: selJobId);
          final punched = records.hasPunchedOn(key, jobId: selJobId);
          final ot = records.overtimeOf(key, jobId: selJobId);
          final autoOt = job != null && job.effectiveAutoOvertime(day)
              ? records.autoOvertimeOf(key, job.standardWorkMinutes, jobId: selJobId)
              : 0.0;

          final stateText = [
            if (punched) '该天有打卡记录（按打卡计薪）',
            switch (mark) {
              null => '当前：按排班自动判断',
              DayMark(isWork: true) => '当前：已标记工作日',
              DayMark(isLeave: true) => '当前：已标记请假',
              _ => '当前：已标记休息日',
            },
            if (ot > 0) '已记加班 ${formatQuantity(ot)} 小时',
            if (autoOt > 0) '自动加班 ${formatQuantity(autoOt)} 小时',
          ].join(' · ');

          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${day.month}月${day.day}日 · 周$weekday',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: sheetContext.colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (multiJob)
                      // 全部模式：各工作明细行，行即选择器
                      Text(
                        '各工作明细 · 合计 ${widget.currency}${formatMoney(earningsOf(settings, records, start: day, end: day))}',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sheetContext.tokens.muted,
                        ),
                      )
                    else
                      Text(
                        stateText,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sheetContext.tokens.muted,
                        ),
                      ),
                    if (multiJob) ...[
                      const SizedBox(height: 10),
                      for (final j in settings.jobs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _DayJobRow(
                            job: j,
                            selected: j.id == selJobId,
                            status: _jobDayStatus(
                              settings,
                              records,
                              key,
                              day,
                              j,
                            ),
                            onTap: () => setSheetState(() => selJobId = j.id),
                          ),
                        ),
                    ],
                    const SizedBox(height: 14),
                    if (!punched) ...[
                      _MarkOption(
                        icon: LucideIcons.briefcase,
                        label: job?.calcMode == CalcMode.hourly
                            ? '标记为工作日（输入工时）'
                            : '标记为工作日',
                        value: 'work',
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!punched) ...[
                      _MarkOption(
                        icon: LucideIcons.leaf,
                        label: '标记为休息日',
                        value: 'rest',
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (!punched) ...[
                      _MarkOption(
                        icon: LucideIcons.plane,
                        label: '标记为请假',
                        value: 'leave',
                      ),
                      const SizedBox(height: 8),
                    ],
                    // 仅工作状态（有打卡或标记为工作日）才可记加班
                    if (punched || mark?.isWork == true) ...[
                      _MarkOption(
                        icon: LucideIcons.zap,
                        label: '记加班（输入小时）',
                        value: 'overtime',
                      ),
                    ],
                    if (mark != null && !punched) ...[
                      const SizedBox(height: 8),
                      _MarkOption(
                        icon: LucideIcons.eraser,
                        label: '清除标记',
                        value: 'clear',
                      ),
                    ],
                    if (ot > 0) ...[
                      const SizedBox(height: 8),
                      _MarkOption(
                        icon: LucideIcons.eraser,
                        label: '清除加班',
                        value: 'clearOvertime',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    // 等底部弹层退场动画结束后再更新数据，
    // 避免统计页整页重建与退场动画同帧执行导致画面抖动。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    final job = settings.jobById(selJobId);
    switch (result) {
      case 'rest':
        await records.setMark(key, DayMark.rest(), jobId: selJobId);
      case 'leave':
        await records.setMark(key, DayMark.leave(), jobId: selJobId);
      case 'clear':
        await records.setMark(key, null, jobId: selJobId);
      case 'work':
        if (job?.calcMode == CalcMode.hourly) {
          final hours = await _showHoursDialog(title: '输入工时', hint: '当天工时');
          if (hours == null || hours <= 0) return;
          await records.setMark(key, DayMark.work(hours), jobId: selJobId);
        } else {
          await records.setMark(key, const DayMark.work(0), jobId: selJobId);
        }
      case 'overtime':
        final hours = await _showHoursDialog(title: '记加班', hint: '加班小时数');
        if (hours == null || hours <= 0) return;
        await records.setOvertime(key, hours, jobId: selJobId);
      case 'clearOvertime':
        await records.setOvertime(key, null, jobId: selJobId);
    }
  }

  Future<double?> _showHoursDialog({
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController(text: '8');
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: hint, suffixText: '小时'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 日历当日数据弹层中的单项统计（标签 + 数值 + 可选副行）。
class _DayStat extends StatelessWidget {
  const _DayStat({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final muted = context.tokens.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: context.colors.onSurface,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(
            sub!,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ],
      ],
    );
  }
}

/// 日历弹层工作明细行：色点 + 名称 + 当日状态，点击选中该工作。
class _DayJobRow extends StatelessWidget {
  const _DayJobRow({
    required this.job,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final Job job;
  final bool selected;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? job.color.withValues(alpha: 0.1)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: job.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                job.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? scheme.onSurface : muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? job.color : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标记选项行。
class _MarkOption extends StatelessWidget {
  const _MarkOption({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Pressable(
      onTap: () => Navigator.pop(context, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: scheme.primary),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日历显示指标切换：工时 / 工资。
class _MetricToggle extends StatelessWidget {
  const _MetricToggle({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final showHours = settings.calendarShowsHours;
    return Pressable(
      onTap: () => settings.setCalendarShowsHours(!showHours),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              showHours ? LucideIcons.clock : LucideIcons.coins,
              size: 13,
              color: scheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              showHours ? '工时' : '工资',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月份切换箭头按钮。
class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? muted.withValues(alpha: 0.4) : muted,
        ),
      ),
    );
  }
}

/// 近 6 个月月度收入柱状图。
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({
    required this.settings,
    required this.records,
    required this.currency,
    this.jobId,
  });

  final SettingsController settings;
  final RecordsController records;
  final String currency;

  /// 工作筛选：null = 全部。
  final String? jobId;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final now = DateTime.now();

    final bars = <BarChartGroupData>[];
    double maxVal = 0;
    final months = <DateTime>[];
    for (var i = 5; i >= 0; i--) {
      months.add(DateTime(now.year, now.month - i, 1));
    }
    for (final (i, month) in months.indexed) {
      final value = netEarningsOfMonth(settings, records, month, jobId: jobId);
      if (value > maxVal) maxVal = value;
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              width: 26,
              borderRadius: BorderRadius.circular(7),
              color: i == months.length - 1
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.32),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '近 6 个月收入',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.25 == 0 ? 10 : maxVal * 1.25,
                  barGroups: bars,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox.shrink();
                          }
                          final isCurrent = i == months.length - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${months[i].month}月',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isCurrent ? scheme.primary : muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, idx, rod, i) => BarTooltipItem(
                        '$currency${rod.toY.toStringAsFixed(rod.toY == rod.toY.roundToDouble() ? 0 : 2)}',
                        TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 记提成弹层：按月录入提成金额（归属选中的工作），计入当月及以上粒度统计。
Future<void> _showCommissionSheet(
  BuildContext context,
  SettingsController settings,
  RecordsController records, {
  String? jobId,
}) async {
  if (settings.jobs.isEmpty) return;
  final now = DateTime.now();
  var month = DateTime(now.year, now.month);
  final controller = TextEditingController();
  var selJobId = jobId;
  if (settings.jobById(selJobId ?? '') == null) {
    selJobId = settings.activeJobId ?? settings.jobs.first.id;
  }

  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final scheme = sheetContext.colors;
        final muted = sheetContext.tokens.muted;
        final isCurrentMonth =
            month.year == now.year && month.month == now.month;
        final existing = records.commissionOf(month, jobId: selJobId);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '记提成',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MonthArrow(
                    icon: LucideIcons.chevronLeft,
                    onTap: () => setSheetState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Text(
                    '${month.year}年${month.month}月',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 18),
                  _MonthArrow(
                    icon: LucideIcons.chevronRight,
                    onTap: isCurrentMonth
                        ? null
                        : () => setSheetState(
                            () => month = DateTime(month.year, month.month + 1),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                existing > 0
                    ? '当月已记提成 ${settings.currency}${formatMoney(existing)}，保存将覆盖'
                    : '按月录入，计入本月、今年与累计统计',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              if (settings.jobs.length > 1) ...[
                const SizedBox(height: 12),
                JobChips(
                  jobs: settings.jobs,
                  selectedJobId: selJobId,
                  onSelect: (id) {
                    if (id != null) {
                      setSheetState(() => selJobId = id);
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: '输入当月提成金额',
                  suffixText: settings.currency,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (existing > 0)
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, 'clear'),
                      child: Text(
                        '清除',
                        style: TextStyle(
                          color: sheetContext.tokens.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, 'save'),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  // 等底部弹层退场动画结束后再更新数据，避免整页重建与退场动画同帧导致抖动。
  if (result == null) return;
  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (result == 'clear') {
    await records.setCommission(month, null, jobId: selJobId);
  } else if (result == 'save') {
    final value = double.tryParse(controller.text.trim());
    if (value != null && value > 0) {
      await records.setCommission(month, value, jobId: selJobId);
    }
  }
}
