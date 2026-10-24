import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:xinji/app/theme/app_tokens.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/core/utils/format.dart';
import 'package:xinji/core/widgets/animated_stat_number.dart';
import 'package:xinji/core/widgets/page_header.dart';
import 'package:xinji/core/widgets/pressable.dart';
import 'package:xinji/features/records/data/punch_record.dart';
import 'package:xinji/features/records/state/earnings.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 上班进行中时，汇总卡的工时/收入需要随时间增长。
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final records = context.watch<RecordsController>();
    final job = settings.activeJob;
    final jobId = job?.id;
    final today = dayKeyOf(DateTime.now());
    final hours = records.dayHoursOf(today, jobId: jobId);
    // 今日收入（税后）：开启个税时按今日收入占比分摊本月个税
    final total = netEarningsOfDay(settings, records, DateTime.now(), jobId: jobId);
    final todayTax = earningsOf(
              settings,
              records,
              start: DateTime.now(),
              end: DateTime.now(),
              jobId: jobId,
            ) -
            total;
    final rateLabel = switch (job?.calcMode) {
      CalcMode.fixedDaily => '日薪',
      CalcMode.monthly => '月薪',
      _ => '时薪',
    };
    final rateValue = job == null
        ? '—'
        : '${settings.currency}${_trim(switch (job.calcMode) {
            CalcMode.hourly => job.hourlyRate,
            CalcMode.fixedDaily => job.dailyWage,
            CalcMode.monthly => job.monthlySalary,
          })}';
    // 本月预计个税：开启个税的工作按当月至今税前收入计税（自然月口径）
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final showTax = job != null && taxEffectiveInMonth(job, month);
    final monthTax = showTax
        ? taxOfMonth(settings, records, month, jobId: jobId)
        : 0.0;
    // 今日加班时长：手动加班 + 自动加班（开启后超出标准工时的部分）
    final otHours = job == null
        ? 0.0
        : records.overtimeHoursBetween(
                start: now,
                end: now,
                jobId: jobId,
              ) +
              (job.effectiveAutoOvertime(now)
                  ? records.autoOvertimeHours(
                      job.standardWorkMinutes,
                      start: now,
                      end: now,
                      jobId: jobId,
                    )
                  : 0.0);
    // 今日加班费：加班时长 × 加班时薪（加班费开关关闭时为 null，只显示时长）
    final otPay = job != null && job.effectiveOvertimePaid(now)
        ? otHours * job.overtimeRate
        : null;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 10,
          16,
          120,
        ),
        children: [
          // 大标题：跟随页面滚动
          const PageHeader(title: '今日'),
          // 多工作时：今日合计卡（全部工作总览，点击行切换当前工作）
          if (settings.jobs.length > 1) ...[
            _TodaySummaryCard(
              settings: settings,
              records: records,
              currency: settings.currency,
            ),
            const SizedBox(height: 16),
          ],
          _TodayHero(
            total: total,
            todayTax: todayTax,
            hours: hours,
            currency: settings.currency,
            rateLabel: rateLabel,
            rateValue: rateValue,
            monthTax: monthTax,
            showTax: showTax,
            otHours: otHours,
            otPay: otPay,
            heroTags: job?.heroTags ?? kDefaultHeroTags,
          ),
          const SizedBox(height: 16),
          _PunchCard(dateKey: today, jobId: jobId),
        ],
      ),
    );
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// 多工作今日合计卡：全部工作今日收入总览，点击行切换当前工作。
class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.settings,
    required this.records,
    required this.currency,
  });

  final SettingsController settings;
  final RecordsController records;
  final String currency;

  /// 行右侧状态：有收入/工时显示金额与工时，其次标记、排班休息、未打卡。
  String _statusOf(Job job, String today, DateTime now) {
    final mark = records.markOf(today, jobId: job.id);
    if (mark != null) {
      if (mark.isRest) return '休息';
      if (mark.isLeave) return '请假';
      if (mark.isWork) return '已标记';
    }
    final earn = earningsOf(
      settings,
      records,
      start: now,
      end: now,
      jobId: job.id,
    );
    final hours = records.dayHoursOf(today, jobId: job.id);
    if (earn > 0 || hours > 0) {
      return '$currency${formatMoney(earn)} · ${formatHours(hours)}';
    }
    if (job.isScheduledRest(now)) return '排班休息';
    return '未打卡';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final now = DateTime.now();
    final today = dayKeyOf(now);
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
    // 今日合计（税后）：开启个税的工作按收入占比分摊本月个税
    final total = netEarningsOfDay(settings, records, now);
    // 全部口径本月预计个税：各工作分别计税后求和（分段口径按月判定）
    final month = DateTime(now.year, now.month);
    final anyTax = settings.jobs.any((j) => taxEffectiveInMonth(j, month));
    final totalTax = anyTax
        ? taxOfMonth(settings, records, month)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日合计',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${now.month}月${now.day}日 · 周$weekday',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedStatNumber(
              value: total,
              currency: currency,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -1.2,
                color: scheme.onSurface,
              ),
            ),
            if (anyTax) ...[
              const SizedBox(height: 6),
              Text(
                '本月预计个税 -$currency${formatMoney(totalTax)}（各工作独立计税）',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            for (final job in settings.jobs)
              _TodayJobRow(
                job: job,
                selected: job.id == settings.activeJobId,
                status: _statusOf(job, today, now),
                currency: currency,
                onTap: () => settings.setActiveJobId(job.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// 合计卡内单个工作行：色点 + 名称 + 状态，点击切换当前工作。
class _TodayJobRow extends StatelessWidget {
  const _TodayJobRow({
    required this.job,
    required this.selected,
    required this.status,
    required this.currency,
    required this.onTap,
  });

  final Job job;
  final bool selected;
  final String status;
  final String currency;
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? job.color.withValues(alpha: 0.08)
              : Colors.transparent,
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
                boxShadow: [
                  BoxShadow(
                    color: job.color.withValues(alpha: 0.4),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
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

/// 顶部今日汇总卡。
class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.total,
    this.todayTax = 0,
    required this.hours,
    required this.currency,
    required this.rateLabel,
    required this.rateValue,
    this.monthTax = 0,
    this.showTax = false,
    this.otHours = 0,
    this.otPay,
    this.heroTags = kDefaultHeroTags,
  });

  final double total;

  /// 今日分摊个税（开启个税时，今日收入为扣除该金额后的税后值）。
  final double todayTax;
  final double hours;
  final String currency;
  final String rateLabel;
  final String rateValue;

  /// 本月预计个税（开启个税时显示）。
  final double monthTax;
  final bool showTax;

  /// 今日加班时长（手动 + 自动；大于 0 时显示）。
  final double otHours;

  /// 今日加班费（加班费开关关闭时为 null，只显示时长）。
  final double? otPay;

  /// 显示的标签及顺序（工时/加班/薪资/个税，每工作独立）。
  final List<String> heroTags;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final now = DateTime.now();
    final weekday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日收入',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '${now.month}月${now.day}日 · 周$weekday',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedStatNumber(
              value: total,
              currency: currency,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 46,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -1.5,
                color: scheme.onSurface,
              ),
            ),
            if (todayTax > 0) ...[
              const SizedBox(height: 6),
              Text(
                '今日分摊个税 -$currency${formatMoney(todayTax)}',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 标签自动换行，超出宽度不截断；顺序与可见性按工作的 heroTags
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                for (final tag in heroTags)
                  switch (tag) {
                    'hours' => _HeroStat(
                      icon: LucideIcons.clock,
                      label: '工时',
                      value: formatHours(hours),
                    ),
                    'overtime' when otHours > 0 => _HeroStat(
                      icon: LucideIcons.zap,
                      label: '加班',
                      // 加班费开启时显示「金额 · 时长」，关闭时只显示时长
                      value: (otPay == null)
                          ? formatHours(otHours)
                          : '$currency${formatMoney(otPay!)} · ${formatHours(otHours)}',
                    ),
                    'rate' => _HeroStat(
                      icon: LucideIcons.coins,
                      label: rateLabel,
                      value: rateValue,
                    ),
                    'tax' when showTax => _HeroStat(
                      icon: LucideIcons.receipt,
                      label: '本月预计个税',
                      value: '-$currency${formatMoney(monthTax)}',
                    ),
                    _ => const SizedBox.shrink(),
                  },
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final muted = context.tokens.muted;
    return Row(
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: context.colors.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 上下班打卡卡片：可多次打卡，实时计算上班总时长。
/// 定时刷新由 [TodayPage] 的 ticker 统一驱动。
class _PunchCard extends StatelessWidget {
  const _PunchCard({required this.dateKey, this.jobId});

  final String dateKey;

  /// 归属工作 id（当前选中工作）。
  final String? jobId;

  String _fmtTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// 跨天上班卡的时间标注：昨日显示「昨日 HH:mm」，更早显示日期。
  String _fmtCarryTime(DateTime time) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final t = _fmtTime(time);
    if (time.year == yesterday.year &&
        time.month == yesterday.month &&
        time.day == yesterday.day) {
      return '昨日 $t';
    }
    return '${time.month}/${time.day} $t';
  }

  String _fmtDuration(Duration d) {
    if (d.inMinutes == 0) return '刚开始';
    return formatHours(d.inMinutes / 60);
  }

  Future<void> _punch(BuildContext context, bool isIn) async {
    await context.read<RecordsController>().addPunch(isIn, jobId: jobId);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final records = context.watch<RecordsController>();
    final scheme = context.colors;
    final muted = context.tokens.muted;
    final simple = settings.simplePunch;
    final punches = records.punchesOf(dateKey, jobId: jobId);
    // 跨天夜班：时间线补充显示前日的上班卡，避免只看到下班卡
    final carryIn = records.carryOverIn(dateKey, jobId: jobId);
    final displayPunches = [
      ?carryIn,
      ...punches,
    ];
    final working = records.isWorkingToday(dateKey, jobId: jobId);
    final total = records.totalWorkTime(dateKey, jobId: jobId);

    final status = working
        ? '工作中 · 已工作 ${_fmtDuration(total)}'
        : punches.isEmpty
        ? simple
              ? '点击打卡，一键完成今日记录'
              : '今天还没有打卡'
        : simple
        ? '已打卡 · 今日共 ${_fmtDuration(total)}'
        : '已下班 · 今日共 ${_fmtDuration(total)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    working ? LucideIcons.briefcase : LucideIcons.coffee,
                    size: 19,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '今日打卡',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: working ? scheme.primary : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (punches.isNotEmpty)
                  Pressable(
                    onTap: () => simple
                        ? context
                              .read<RecordsController>()
                              .undoLastSession(jobId: jobId)
                        : context
                              .read<RecordsController>()
                              .undoLastPunch(dateKey, jobId: jobId),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.undo2, size: 14, color: muted),
                          const SizedBox(width: 4),
                          Text(
                            '撤销',
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 打卡按钮
            if (simple)
              _SimplePunchArea(
                jobId: jobId,
                working: working,
                hasPunches: punches.isNotEmpty,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _PunchButton(
                      icon: LucideIcons.logIn,
                      label: '上班打卡',
                      active: !working,
                      onTap: () => _punch(context, true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PunchButton(
                      icon: LucideIcons.logOut,
                      label: '下班打卡',
                      active: working,
                      onTap: () => _punch(context, false),
                    ),
                  ),
                ],
              ),

            // 打卡记录：竖排时间线
            if (displayPunches.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 14),
              _buildTimeline(
                displayPunches,
                working,
                scheme,
                muted,
                carryIn: carryIn,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 竖排打卡时间线：时间 · 圆点竖线 · 上下班，段与段之间显示时长。
  /// [carryIn] 为跨天时段的前日上班卡，时间标注昨日/日期。
  Widget _buildTimeline(
    List<PunchRecord> punches,
    bool working,
    ColorScheme scheme,
    Color muted, {
    PunchRecord? carryIn,
  }) {
    final widgets = <Widget>[];

    for (var i = 0; i < punches.length; i++) {
      final punch = punches[i];
      final isCarry = carryIn != null && i == 0;
      final isLast = i == punches.length - 1;
      final next = isLast ? null : punches[i + 1];

      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              child: Text(
                isCarry ? _fmtCarryTime(punch.time) : _fmtTime(punch.time),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: isCarry ? 11.5 : 14.5,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: isCarry ? muted : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: punch.isIn ? scheme.primary : scheme.tertiary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (punch.isIn ? scheme.primary : scheme.tertiary)
                        .withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              punch.isIn ? '上班打卡' : '下班打卡',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: punch.isIn ? scheme.primary : scheme.onSurface,
              ),
            ),
            if (punch.isIn && isLast && working) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '进行中',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

      // 连接线段：有下一条打卡，或上班进行中
      Duration? segment;
      var ongoing = false;
      if (punch.isIn) {
        if (next != null && !next.isIn) {
          segment = next.time.difference(punch.time);
        } else if (next == null && working) {
          segment = DateTime.now().difference(punch.time);
          ongoing = true;
        }
      }
      if (next != null || segment != null) {
        widgets.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 48),
              const SizedBox(width: 12),
              Container(
                width: 11,
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: 22,
                  decoration: BoxDecoration(
                    color: ongoing
                        ? scheme.primary.withValues(alpha: 0.45)
                        : scheme.outlineVariant.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (segment != null)
                Text(
                  _fmtDuration(segment),
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ongoing ? scheme.primary : muted,
                  ),
                ),
            ],
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

/// 简洁模式打卡区：
/// - 日薪/月薪已设上下班时间：一键生成整天闭合时段，当天直接计薪；
/// - 时薪（或时间无效）：输入工时后点击打卡，生成 now-工时 → now 的闭合时段；
/// - 遗留进行中的上班卡（精准模式切换过来）：提供下班打卡闭合。
class _SimplePunchArea extends StatefulWidget {
  const _SimplePunchArea({
    this.jobId,
    required this.working,
    required this.hasPunches,
  });

  final String? jobId;
  final bool working;

  /// 今日已有打卡（含跨天未闭合的上班卡）：不再显示一键打卡。
  final bool hasPunches;

  @override
  State<_SimplePunchArea> createState() => _SimplePunchAreaState();
}

class _SimplePunchAreaState extends State<_SimplePunchArea> {
  final _hoursCtrl = TextEditingController(text: '8');

  @override
  void dispose() {
    _hoursCtrl.dispose();
    super.dispose();
  }

  String _fmtMinutes(int minutes) {
    final m = ((minutes % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _punchOut() async {
    await context.read<RecordsController>().addPunch(false, jobId: widget.jobId);
    HapticFeedback.mediumImpact();
  }

  /// 日薪/月薪一键打卡：生成 workStart → workEnd 的闭合时段（跨次日自动 +1 天）。
  Future<void> _punchFixedTimes(Job job) async {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final start = base.add(Duration(minutes: job.workStart));
    var end = base.add(Duration(minutes: job.workEnd));
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    await context
        .read<RecordsController>()
        .punchSession(start, end, jobId: widget.jobId);
    HapticFeedback.mediumImpact();
  }

  /// 时薪输入工时打卡：生成 (now - 工时) → now 的闭合时段。
  Future<void> _punchHours() async {
    final hours = double.tryParse(_hoursCtrl.text.trim());
    if (hours == null || hours <= 0 || hours > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 0~24 之间的工时')),
      );
      return;
    }
    final now = DateTime.now();
    await context.read<RecordsController>().punchSession(
          now.subtract(Duration(minutes: (hours * 60).round())),
          now,
          jobId: widget.jobId,
        );
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    // 遗留的进行中上班卡：与精准模式一致提供下班闭合
    if (widget.working) {
      return _PunchButton(
        icon: LucideIcons.logOut,
        label: '下班打卡',
        active: true,
        onTap: _punchOut,
      );
    }
    // 今日已打卡：时间线 + 撤销即可
    if (widget.hasPunches) return const SizedBox.shrink();

    final job = widget.jobId == null
        ? null
        : settings.jobById(widget.jobId!);
    final fixedSalary =
        job != null &&
        (job.calcMode == CalcMode.fixedDaily || job.calcMode == CalcMode.monthly);
    final hasTimes = job != null && job.workEnd != job.workStart;

    // 日薪/月薪 + 已设上下班时间：一键完成今日出勤
    if (fixedSalary && hasTimes) {
      final overnight = job.workEnd < job.workStart;
      final caption = overnight
          ? '${_fmtMinutes(job.workStart)} – 次日${_fmtMinutes(job.workEnd)}'
          : '${_fmtMinutes(job.workStart)} – ${_fmtMinutes(job.workEnd)}';
      return _OneTapPunchButton(caption: caption, onTap: () => _punchFixedTimes(job));
    }

    // 时薪（或时间无效）：输入工时后打卡
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: TextField(
              controller: _hoursCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: '工时',
                suffixText: '小时',
                filled: true,
                fillColor: scheme.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: BorderSide.none,
                ),
                hintStyle: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PunchButton(
            icon: LucideIcons.zap,
            label: '打卡',
            active: true,
            onTap: _punchHours,
          ),
        ),
      ],
    );
  }
}

/// 一键打卡按钮：主色填充 + 时段说明小字。
class _OneTapPunchButton extends StatelessWidget {
  const _OneTapPunchButton({required this.caption, required this.onTap});

  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 52,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.zap, size: 18, color: scheme.onPrimary),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '打卡',
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: scheme.onPrimary,
                  ),
                ),
                Text(
                  caption,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: scheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 打卡按钮：激活时主色填充，未激活时置灰。
class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 52,
        decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? scheme.onPrimary : muted),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: active ? scheme.onPrimary : muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
