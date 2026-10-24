import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/app/theme/app_tokens.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/core/widgets/page_header.dart';
import 'package:xinji/core/widgets/pressable.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

/// 设置主页：按主题分组的入口列表，具体设置在二级页面中。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

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
          const PageHeader(title: '设置'),
          Card(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.briefcase,
                  label: '我的工作',
                  value: '${settings.jobs.length} 份工作',
                  onTap: () => _push(context, const _JobsPage()),
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.bell,
                  label: '通知',
                  value: _notificationsSummary(settings),
                  onTap: () => _push(context, const _NotificationsPage()),
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.palette,
                  label: '外观',
                  value: _themeSummary(settings),
                  onTap: () => _push(context, const _AppearanceSettingsPage()),
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.database,
                  label: '数据',
                  value: '',
                  onTap: () => _push(context, const _DataSettingsPage()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 关于
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          LucideIcons.wallet,
                          size: 22,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '薪迹',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '简洁的工资记录工具 · v1.39.1',
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.tokens.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _AboutTile(
                    icon: LucideIcons.user,
                    label: '作者',
                    value: '阿呆',
                    onTap: () => _openUrl('https://adaiblog.github.io/'),
                  ),
                  const _Divider(),
                  _AboutTile(
                    icon: LucideIcons.code,
                    label: '源代码',
                    value: 'github.com/ADAIBLOG/XinJi',
                    onTap: () => _openUrl('https://github.com/ADAIBLOG/XinJi'),
                  ),
                  const _Divider(),
                  _AboutTile(
                    icon: LucideIcons.heart,
                    label: 'UI 设计灵感 · Streak',
                    value: '日历方块、状态配色与底部导航样式参考 Streak（习惯打卡应用）设计，特此感谢。',
                    onTap: () => _openUrl('https://github.com/InlitX/streak'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

/// 打卡模式选择：1=简洁（一键打卡） 2=精准（上下班两次打卡）。每工作独立。
Future<void> _configPunchMode(
  BuildContext context,
  SettingsController settings,
  Job job,
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
              '打卡模式',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: sheetContext.colors.onSurface,
              ),
            ),
            const SizedBox(height: 14),
            _PunchModeOption(
              icon: LucideIcons.zap,
              title: '简洁',
              subtitle: '今日页一键打卡：日薪/月薪设好上下班时间后，点击打卡直接完成今日出勤；时薪输入工时即入账。',
              selected: job.punchMode == 1,
              onTap: () => Navigator.pop(sheetContext, 1),
            ),
            const SizedBox(height: 10),
            _PunchModeOption(
              icon: LucideIcons.watch,
              title: '精准',
              subtitle: '上下班两次打卡，实时累计工时（当前逻辑）。',
              selected: job.punchMode == 2,
              onTap: () => Navigator.pop(sheetContext, 2),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked != null && picked != job.punchMode) {
    await settings.updateJob(job.copyWith(punchMode: picked));
  }
}

/// 今日页收入卡标签配置：选择显示哪些标签（开关）及排列顺序（上移/下移）。
/// 列表顺序即今日页显示顺序；关闭的标签移到列表末尾（不再显示）。
Future<void> _configHeroTags(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _HeroTagsSheet(
      initialTags: [...job.heroTags],
      currency: settings.currency,
      onSave: (tags) =>
          settings.updateJob(job.copyWith(heroTags: [...tags])),
    ),
  );
}

/// 今日页标签编辑弹层：可见项按顺序在前（可排序），隐藏项灰显在后。
class _HeroTagsSheet extends StatefulWidget {
  const _HeroTagsSheet({
    required this.initialTags,
    required this.currency,
    required this.onSave,
  });

  final List<String> initialTags;
  final String currency;
  final Future<void> Function(List<String> tags) onSave;

  @override
  State<_HeroTagsSheet> createState() => _HeroTagsSheetState();
}

class _HeroTagsSheetState extends State<_HeroTagsSheet> {
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _tags = [...widget.initialTags];
  }

  (IconData, String, String) _metaOf(String tag) => switch (tag) {
    'hours' => (LucideIcons.clock, '工时', '当日打卡总时长'),
    'overtime' => (LucideIcons.zap, '加班', '当日有加班时显示时长'),
    'rate' => (LucideIcons.coins, '薪资', '时薪 / 日薪 / 月薪'),
    'tax' => (LucideIcons.receipt, '个税', '开启个税时显示本月预计扣税'),
    _ => (LucideIcons.circle, tag, ''),
  };

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _tags.length) return;
    setState(() {
      final t = _tags.removeAt(index);
      _tags.insert(target, t);
    });
  }

  void _toggle(String tag, bool visible) {
    setState(() {
      _tags.remove(tag);
      if (visible) _tags.add(tag);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    // 显示全部标签：可见项按顺序在前，隐藏项在后
    final rows = [
      ..._tags,
      for (final t in kHeroTagIds)
        if (!_tags.contains(t)) t,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日页标签',
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '选择今日收入卡显示的标签及顺序（${widget.currency}金额标签过多时自动换行）。',
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          for (final (i, tag) in rows.indexed)
            Builder(
              builder: (context) {
                final (icon, name, desc) = _metaOf(tag);
                final visible = i < _tags.length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(icon, size: 17, color: visible ? scheme.primary : muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: visible ? scheme.onSurface : muted,
                              ),
                            ),
                            Text(
                              desc,
                              style: TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 排序按钮：仅可见项可用
                      _IconBtn(
                        icon: LucideIcons.chevronUp,
                        onTap: visible && i > 0 ? () => _move(i, -1) : null,
                      ),
                      _IconBtn(
                        icon: LucideIcons.chevronDown,
                        onTap: visible && i < _tags.length - 1
                            ? () => _move(i, 1)
                            : null,
                      ),
                      Switch(value: visible, onChanged: (v) => _toggle(tag, v)),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _tags
                  ..clear()
                  ..addAll(kDefaultHeroTags)),
                child: const Text('恢复默认'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await widget.onSave(_tags);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 弹层内的小图标按钮（上移/下移）。
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.tokens.muted;
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: onTap == null ? muted.withValues(alpha: 0.35) : muted),
    );
  }
}

/// 用外部浏览器打开链接。
Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String _jobSummary(SettingsController s, Job job) => switch (job.calcMode) {
  CalcMode.hourly => '${s.currency}${_trim(job.hourlyRate)}/小时',
  CalcMode.fixedDaily => '${s.currency}${_trim(job.dailyWage)}/天',
  CalcMode.monthly => '${s.currency}${_trim(job.monthlySalary)}/月',
};

String _themeSummary(SettingsController s) => switch (s.themeMode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

/// 设置主页「通知」行的摘要文字。
String _notificationsSummary(SettingsController s) {
  final on = s.jobs.where((j) => j.punchReminders).length;
  if (on == 0) return '关闭';
  final total = s.jobs
      .where((j) => j.punchReminders)
      .fold<int>(0, (sum, j) => sum + j.reminderMinutes.length);
  return '$on 份工作 · $total 个提醒';
}

/// 「通知」页：打卡提醒管理——每份工作独立的开关 + 自定义提醒时间列表
/// （与上下班时间无关，可添加多个时间点到点弹应用通知）。
class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage();

  String _timeLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: const Text('通知'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '到点弹出应用通知提醒打卡，与上下班时间无关，可设多个提醒时间（应用需保持运行）。',
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.tokens.muted,
              ),
            ),
          ),
          for (final (i, job) in settings.jobs.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: job.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            job.name,
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: context.colors.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: job.punchReminders,
                          onChanged: (v) => settings.updateJob(
                            job.copyWith(punchReminders: v),
                          ),
                        ),
                      ],
                    ),
                    if (job.punchReminders) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final minute in job.reminderMinutes)
                            InputChip(
                              avatar: Icon(
                                LucideIcons.clock,
                                size: 14,
                                color: context.colors.primary,
                              ),
                              label: Text(_timeLabel(minute)),
                              onDeleted: () => settings.updateJob(
                                job.copyWith(
                                  reminderMinutes: [
                                    ...job.reminderMinutes.where(
                                      (m) => m != minute,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ActionChip(
                            avatar: Icon(
                              LucideIcons.plus,
                              size: 14,
                              color: context.colors.primary,
                            ),
                            label: const Text('添加时间'),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (picked == null) return;
                              final minute =
                                  picked.hour * 60 + picked.minute;
                              if (job.reminderMinutes.contains(minute)) return;
                              final next = [...job.reminderMinutes, minute]
                                ..sort();
                              await settings.updateJob(
                                job.copyWith(reminderMinutes: next),
                              );
                            },
                          ),
                        ],
                      ),
                      if (job.reminderMinutes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '尚未设置提醒时间，点击「添加时间」创建。',
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.tokens.muted,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「我的工作」页：工作列表（每份工作独立的薪资/时间/排班/打卡/个税）+ 新增工作，
/// 以及全局的货币符号。
class _JobsPage extends StatelessWidget {
  const _JobsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text('我的工作')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                for (var i = 0; i < settings.jobs.length; i++) ...[
                  if (i > 0) const _Divider(),
                  _SettingsRow(
                    icon: LucideIcons.briefcase,
                    label: settings.jobs[i].name,
                    value: _jobSummary(settings, settings.jobs[i]),
                    onTap: () => _push(
                      context,
                      _JobSettingsPage(jobId: settings.jobs[i].id),
                    ),
                  ),
                ],
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.plus,
                  label: '新增工作',
                  value: '',
                  onTap: () {
                    // 草稿模式：进入编辑页，点「完成」才保存，返回则丢弃
                    final job = context
                        .read<SettingsController>()
                        .createDraftJob();
                    _push(
                      context,
                      _JobSettingsPage(jobId: job.id, isNew: true),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.circleDollarSign,
                  label: '货币符号',
                  value: settings.currency,
                  onTap: () => _pickCurrency(context, settings),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 分段开关的显示名。
String _jobSwitchLabel(JobSwitch s) => switch (s) {
  JobSwitch.tax => '个税扣除',
  JobSwitch.overtimePaid => '加班费',
  JobSwitch.autoOvertime => '固定上班时间',
};

/// 切换分段开关（个税/加班费/自动加班）：
/// 存在今天之前的历史数据且状态实际变化时，弹层让用户选择——
/// 「仅今后生效」：之前的记录保持原口径，从今天起新值；
/// 「同步当月」：本月整月按新设置计算，之前的月份保持不变。
/// 无历史数据（或全部为今天）时直接生效，不打扰。
Future<void> _onJobSwitch(
  BuildContext context, {
  required SettingsController settings,
  required RecordsController records,
  required Job job,
  required JobSwitch sw,
  required bool value,
}) async {
  bool current(Job j) => switch (sw) {
    JobSwitch.tax => j.taxEnabled,
    JobSwitch.overtimePaid => j.overtimePaid,
    JobSwitch.autoOvertime => j.autoOvertime,
  };
  if (current(job) == value) return;

  final earliest = records.earliestDataDate(jobId: job.id);
  final today = DateTime.now();
  final hasHistory = earliest != null &&
      DateTime(earliest.year, earliest.month, earliest.day)
          .isBefore(DateTime(today.year, today.month, today.day));

  var fromNowOnly = false;
  // 个税是月度口径：开启当月一起计税、关闭当月一起不计——切换直接
  // 当月整月生效（分段记录 from=当月1日），不按日拆分，无需弹层选择。
  if (sw != JobSwitch.tax && hasHistory) {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_jobSwitchLabel(sw)}：${value ? '开启' : '关闭'}'),
        content: const Text(
          '新设置如何生效？\n\n'
          '· 仅今后生效：今天起按新设置计算，之前的记录保持不变\n'
          '· 同步当月：本月按新设置计算，之前月份保持不变',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'cancel'),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'sync'),
            child: const Text('同步当月'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'now'),
            child: const Text('仅今后生效'),
          ),
        ],
      ),
    );
    if (choice == null || choice == 'cancel') return;
    fromNowOnly = choice == 'now';
  }
  await settings.updateJob(
    job.copyWithSwitch(sw, value, fromNowOnly: fromNowOnly),
  );
}

/// 单份工作设置页：名称、计算模式、薪资、加班、工作时间、打卡模式与跨天分割、
/// 个税扣除、休息日排班、删除。
/// [isNew] 为新增工作流程：AppBar 显示「完成」（点按才保存），返回则丢弃草稿。
class _JobSettingsPage extends StatelessWidget {
  const _JobSettingsPage({required this.jobId, this.isNew = false});

  final String jobId;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final records = context.watch<RecordsController>();
    final job = settings.jobById(jobId);
    if (job == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox());
    }
    void update(Job Function(Job) change) => settings.updateJob(change(job));

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // 中途返回：丢弃未完成的新增草稿
        if (didPop && isNew) settings.discardDraftJob();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(isNew ? '新增工作' : job.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // ── 基本信息 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabelWithIcon(
                      icon: LucideIcons.briefcase,
                      text: '基本信息',
                    ),
                    const SizedBox(height: 12),
                    _SettingsRow(
                      icon: LucideIcons.tag,
                      label: '名称',
                      value: job.name,
                      onTap: () => _editJobName(context, settings, job),
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel('标识色'),
                    _PresetColorPicker(
                      colors: AppPalette.jobColors,
                      selected: job.color,
                      onSelect: (color) {
                        final index = AppPalette.jobColors.indexOf(color);
                        update(
                          (j) => j.copyWith(
                            colorIndex: index == -1 ? j.colorIndex : index,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel('计算模式'),
                    _SegmentedPicker<CalcMode>(
                      items: const [
                        (CalcMode.hourly, '时薪', LucideIcons.clock),
                        (CalcMode.fixedDaily, '日薪', LucideIcons.banknote),
                        (CalcMode.monthly, '月薪', LucideIcons.calendarDays),
                      ],
                      selected: job.calcMode,
                      onChanged: (mode) =>
                          update((j) => j.copyWith(calcMode: mode)),
                    ),
                    if (job.calcMode == CalcMode.monthly) ...[
                      const SizedBox(height: 18),
                      const _FieldLabel('月薪折算方式'),
                      _SegmentedPicker<bool>(
                        items: const [
                          (false, '÷ 21.75', LucideIcons.scale),
                          (true, '÷ 当月天数', LucideIcons.calendarDays),
                        ],
                        selected: job.monthlyByActualDays,
                        onChanged: (v) =>
                            update((j) => j.copyWith(monthlyByActualDays: v)),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          job.monthlyByActualDays
                              ? '出勤一天 = 月薪 ÷ 出勤当月实际天数'
                              : '出勤一天 = 月薪 ÷ 21.75（平均月计薪天数）',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 薪资 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabelWithIcon(
                      icon: LucideIcons.coins,
                      text: '薪资',
                    ),
                    const SizedBox(height: 4),
                    switch (job.calcMode) {
                      CalcMode.fixedDaily => _SettingsRow(
                        icon: LucideIcons.banknote,
                        label: '日薪',
                        value: '${settings.currency}${_trim(job.dailyWage)}/天',
                        onTap: () => _editJobRate(context, settings, job),
                      ),
                      CalcMode.monthly => _SettingsRow(
                        icon: LucideIcons.calendarDays,
                        label: '月薪',
                        value:
                            '${settings.currency}${_trim(job.monthlySalary)}/月',
                        onTap: () => _editJobRate(context, settings, job),
                      ),
                      _ => _SettingsRow(
                        icon: LucideIcons.coins,
                        label: '时薪',
                        value: '${settings.currency}${_trim(job.hourlyRate)}/小时',
                        onTap: () => _editJobRate(context, settings, job),
                      ),
                    },
                    const SizedBox(height: 8),
                    // 加班时薪：仅开启加班费时显示
                    if (job.overtimePaid) ...[
                      _SettingsRow(
                        icon: LucideIcons.zap,
                        label: '加班时薪',
                        value: '${settings.currency}${_trim(job.overtimeRate)}/小时',
                        onTap: () => _editOvertimeRate(context, settings, job),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _FieldLabelWithIcon(
                            icon: LucideIcons.circleDollarSign,
                            text: '加班费',
                          ),
                        ),
                        Switch(
                          value: job.overtimePaid,
                          onChanged: (v) => _onJobSwitch(
                            context,
                            settings: settings,
                            records: records,
                            job: job,
                            sw: JobSwitch.overtimePaid,
                            value: v,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        job.overtimePaid
                            ? '加班工时（手动 + 自动）按加班时薪计入金额。'
                            : '无加班费：只统计加班工时，不增加金额。',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.tokens.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 固定上班时间：开关控制上下班时间设置与自动加班 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _FieldLabelWithIcon(
                            icon: LucideIcons.timer,
                            text: '固定上班时间',
                          ),
                        ),
                        Switch(
                          value: job.autoOvertime,
                          onChanged: (v) => _onJobSwitch(
                            context,
                            settings: settings,
                            records: records,
                            job: job,
                            sw: JobSwitch.autoOvertime,
                            value: v,
                          ),
                        ),
                      ],
                    ),
                    if (job.autoOvertime) ...[
                      const SizedBox(height: 8),
                      _SettingsRow(
                        icon: LucideIcons.sunrise,
                        label: '上班时间',
                        value: _timeLabel(job.workStart),
                        onTap: () => _pickWorkTime(
                          context,
                          settings,
                          job,
                          isStart: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SettingsRow(
                        icon: LucideIcons.sunset,
                        label: '下班时间',
                        value: _timeLabel(job.workEnd),
                        onTap: () => _pickWorkTime(
                          context,
                          settings,
                          job,
                          isStart: false,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '当日打卡工时超出上下班时间标准'
                          '（${_trim(job.standardWorkMinutes / 60.0)} 小时）的部分自动计为加班，'
                          '按加班时薪计入金额；日薪/月薪打完下班卡才计当日工资，'
                          '达到半个工时算整天，不足算半天。',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.muted,
                          ),
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '开启后可设置上班、下班时间，当日工时超出标准工时的部分自动计为加班。',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 打卡 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabelWithIcon(
                      icon: LucideIcons.fingerprint,
                      text: '打卡',
                    ),
                    const SizedBox(height: 4),
                    _SettingsRow(
                      icon: LucideIcons.zap,
                      label: '打卡模式',
                      value: job.punchMode == 1 ? '简洁' : '精准',
                      onTap: () => _configPunchMode(context, settings, job),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _FieldLabelWithIcon(
                            icon: LucideIcons.moonStar,
                            text: '跨天打卡按午夜分割',
                          ),
                        ),
                        Switch(
                          value: job.splitOvernight,
                          onChanged: (v) =>
                              update((j) => j.copyWith(splitOvernight: v)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        job.splitOvernight
                            ? '该工作跨天时段（如昨晚上班、今早下班）按午夜切分，工时分摊到上班与下班两天。'
                            : '不分割：整段工时与打卡记录以下班卡为准，全部归入下班日期。',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.tokens.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsRow(
                      icon: LucideIcons.tags,
                      label: '今日页标签',
                      value: '${job.heroTags.length}/${kHeroTagIds.length}',
                      onTap: () => _configHeroTags(context, settings, job),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 个税 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _FieldLabelWithIcon(
                            icon: LucideIcons.receipt,
                            text: '个税扣除',
                          ),
                        ),
                        Switch(
                          value: job.taxEnabled,
                          onChanged: (v) => _onJobSwitch(
                            context,
                            settings: settings,
                            records: records,
                            job: job,
                            sw: JobSwitch.tax,
                            value: v,
                          ),
                        ),
                      ],
                    ),
                    if (job.taxEnabled) ...[
                      _TaxField(
                        icon: LucideIcons.percent,
                        label: '税率',
                        value: '${_trim(job.taxRate * 100)}%',
                        onTap: () => _editTaxRate(context, settings, job),
                      ),
                      const SizedBox(height: 8),
                      _TaxField(
                        icon: LucideIcons.landmark,
                        label: '起征点',
                        value:
                            '${settings.currency}${_trim(job.taxThreshold)}/月',
                        onTap: () => _editTaxThreshold(context, settings, job),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '按月近似计算：该工作月收入（工资 + 加班 + 提成）超过起征点的部分 × '
                          '税率；多工作各自独立计税，从月度及以上统计中扣除，'
                          '今日、本周与每日图表仍显示税前。',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── 休息日排班 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabelWithIcon(
                      icon: LucideIcons.calendarDays,
                      text: '休息日排班',
                    ),
                    const SizedBox(height: 12),
                    _SegmentedPicker<RestSchedule>(
                      items: const [
                        (RestSchedule.flexible, '无固定', LucideIcons.calendar),
                        (RestSchedule.fixed, '固定休息', LucideIcons.calendarDays),
                        (RestSchedule.alternate, '大小周', LucideIcons.repeat),
                      ],
                      selected: job.restMode,
                      onChanged: (mode) => update(
                        (j) => j.copyWith(
                          restMode: mode,
                          // 切换到大小周时以本周为参照
                          altAnchorMonday:
                              mode == RestSchedule.alternate &&
                                  j.restMode != RestSchedule.alternate
                              ? weekStartOf(DateTime.now())
                              : null,
                        ),
                      ),
                    ),
                    if (job.restMode == RestSchedule.fixed) ...[
                      const SizedBox(height: 16),
                      const _FieldLabel('每周固定休息'),
                      _WeekdayChips(settings: settings, job: job),
                    ],
                    if (job.restMode == RestSchedule.alternate) ...[
                      const SizedBox(height: 16),
                      const _FieldLabel('本周是'),
                      _SegmentedPicker<bool>(
                        items: const [
                          (true, '大周 · 单休', LucideIcons.sun),
                          (false, '小周 · 双休', LucideIcons.moon),
                        ],
                        selected: job.currentWeekIsBig,
                        onChanged: (big) => update(
                          (j) => j.copyWith(
                            altAnchorMonday: weekStartOf(DateTime.now()),
                            altAnchorIsBig: big,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '每周日休，周六隔周休；以本周为参照交替',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.tokens.muted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isNew)
              // 新增工作：页面下方「完成」按钮，点击才保存
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () async {
                      await settings.commitDraftJob();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(
                      '完成',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              )
            else if (settings.jobs.length > 1) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    _SettingsRow(
                      icon: LucideIcons.trash2,
                      label: '删除这份工作',
                      value: '',
                      danger: true,
                      onTap: () => _deleteJob(context, settings, records, job),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 外观二级设置页：主题模式、主题色、休息日/请假标记色。
class _AppearanceSettingsPage extends StatelessWidget {
  const _AppearanceSettingsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text('外观')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('主题模式'),
                  _ThemeModePicker(settings: settings),
                  const SizedBox(height: 14),
                  _OledSwitch(settings: settings),
                  const SizedBox(height: 18),
                  const _FieldLabel('主题色'),
                  _AccentPicker(settings: settings),
                  const SizedBox(height: 18),
                  const _FieldLabel('休息日颜色'),
                  _PresetColorPicker(
                    colors: AppPalette.restColors,
                    selected: settings.restColor,
                    onSelect: settings.setRestColor,
                  ),
                  const SizedBox(height: 18),
                  const _FieldLabel('请假颜色'),
                  _PresetColorPicker(
                    colors: AppPalette.leaveColors,
                    selected: settings.leaveColor,
                    onSelect: settings.setLeaveColor,
                  ),
                  const SizedBox(height: 18),
                  const _FieldLabel('加班日颜色'),
                  _OvertimeColorPicker(settings: settings),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '日历中当日有加班（手动或自动）时，用比正常上班更深的底色标记；'
                      '首位为跟随主题加深。',
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.tokens.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _FieldLabel('底部导航'),
                  _SegmentedPicker<bool>(
                    items: const [
                      (false, '仅图标', LucideIcons.image),
                      (true, '图标 + 文字', LucideIcons.type),
                    ],
                    selected: settings.navBarLabels,
                    onChanged: settings.setNavBarLabels,
                  ),
                  const SizedBox(height: 12),
                  _SegmentedPicker<bool>(
                    items: const [
                      (false, '方形色块', LucideIcons.square),
                      (true, '胶囊色块', LucideIcons.pill),
                    ],
                    selected: settings.navBarCircle,
                    onChanged: settings.setNavBarCircle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数据二级设置页：记录概览、导出/导入备份、清空记录。
class _DataSettingsPage extends StatelessWidget {
  const _DataSettingsPage();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final records = context.watch<RecordsController>();

    return Scaffold(
      appBar: AppBar(title: Text('数据')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.fingerprint,
                  label: '打卡记录',
                  value: '${records.punches.length} 次',
                  onTap: () {},
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.calendarCheck,
                  label: '日期标记',
                  value: '${records.marks.length} 天',
                  onTap: () {},
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.zap,
                  label: '加班记录',
                  value: '${records.overtime.length} 条',
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.upload,
                  label: '导出备份',
                  value: '分享 JSON 备份文件',
                  onTap: () => _exportBackup(context),
                ),
                const _Divider(),
                _SettingsRow(
                  icon: LucideIcons.download,
                  label: '导入备份',
                  value: '从备份文件恢复',
                  onTap: () => _importBackup(
                    context,
                    settings: settings,
                    records: records,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                _SettingsRow(
                  icon: LucideIcons.trash2,
                  label: '清空所有记录',
                  value: '',
                  danger: true,
                  onTap: () => _clearAll(context, records),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// OLED 纯黑背景开关（深色模式下生效）。
class _OledSwitch extends StatelessWidget {
  const _OledSwitch({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final on = settings.oledBlack;
    return Pressable(
      onTap: () => settings.setOledBlack(!on),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: on
              ? context.colors.primary.withValues(alpha: 0.1)
              : context.colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on
                ? context.colors.primary.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.moonStar,
              size: 18,
              color: on ? context.colors.primary : context.tokens.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '纯黑背景（OLED）',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '深色模式使用纯黑背景，OLED 屏幕省电',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.tokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: on, onChanged: settings.setOledBlack),
          ],
        ),
      ),
    );
  }
}

/// 卡片内字段小标题。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Figtree',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.colors.onSurface,
        ),
      ),
    );
  }
}

/// 带图标的字段小标题（与 [_FieldLabel] 同排版，用于开关行）。
class _FieldLabelWithIcon extends StatelessWidget {
  const _FieldLabelWithIcon({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.colors.primary),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 税收卡内字段行：图标 + 标签 + 当前值，点击编辑。
class _TaxField extends StatelessWidget {
  const _TaxField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 15, color: muted),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 68),
      child: Divider(
        height: 1,
        color: context.colors.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 关于卡信息块：小标签在上、内容在下；可选点击跳转（显示箭头）。
class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final muted = context.tokens.muted;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: onTap != null ? primary : muted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: context.colors.onSurface,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.arrowUpRight, size: 15, color: primary),
            ],
          ],
        ),
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: body,
      );
    }
    return Pressable(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: body,
      ),
    );
  }
}

/// 打卡模式选项：标题 + 说明，选中态高亮描边。
class _PunchModeOption extends StatelessWidget {
  const _PunchModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 17, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(LucideIcons.circleCheck, size: 18, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? context.tokens.danger : context.colors.primary;
    final muted = context.tokens.muted;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: danger
                      ? context.tokens.danger
                      : context.colors.onSurface,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight, size: 17, color: muted),
          ],
        ),
      ),
    );
  }
}

/// 通用胶囊分段选择器。
class _SegmentedPicker<T> extends StatelessWidget {
  const _SegmentedPicker({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String, IconData?)> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final (value, label, icon) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == selected
                        ? scheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: value == selected
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 15,
                          color: value == selected
                              ? scheme.onPrimary
                              : context.tokens.muted,
                        ),
                        const SizedBox(width: 6),
                      ],
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: value == selected
                              ? scheme.onPrimary
                              : context.tokens.muted,
                        ),
                        child: Text(label),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 加班日颜色选择：首位「跟随主题加深」+ 自定义色板（按索引持久化）。
class _OvertimeColorPicker extends StatelessWidget {
  const _OvertimeColorPicker({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final selected = settings.overtimeColorIndex;
    Widget chip(Color color, bool isSelected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Pressable(
        onTap: onTap,
        scale: 0.85,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? scheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(
            scheme.primary.withValues(alpha: 0.5),
            selected == -1,
            () => settings.setOvertimeColorIndex(-1),
          ),
          for (var i = 0; i < AppPalette.overtimeColors.length; i++)
            chip(
              AppPalette.overtimeColors[i],
              selected == i,
              () => settings.setOvertimeColorIndex(i),
            ),
        ],
      ),
    );
  }
}

/// 每周固定休息日选择（周一周日多选，按工作配置）。
class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.settings, required this.job});

  final SettingsController settings;
  final Job job;

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final muted = context.tokens.muted;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final set = {...job.fixedRestWeekdays};
                if (!set.remove(i + 1)) set.add(i + 1);
                if (set.isNotEmpty) {
                  settings.updateJob(job.copyWith(fixedRestWeekdays: set));
                }
              },
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: job.fixedRestWeekdays.contains(i + 1)
                        ? scheme.primary
                        : scheme.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: job.fixedRestWeekdays.contains(i + 1)
                          ? scheme.onPrimary
                          : muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.settings});

  final SettingsController settings;

  static const _modes = [
    (ThemeMode.system, '跟随系统', LucideIcons.sunMoon),
    (ThemeMode.light, '浅色', LucideIcons.sun),
    (ThemeMode.dark, '深色', LucideIcons.moon),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final index = _modes.indexWhere((m) => m.$1 == settings.themeMode);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutBack,
              alignment: Alignment(
                index == 0
                    ? -1
                    : index == 1
                    ? 0
                    : 1,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (mode, label, icon) in _modes)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => settings.setThemeMode(mode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: mode == settings.themeMode
                                ? scheme.onPrimary
                                : context.tokens.muted,
                          ),
                          const SizedBox(width: 6),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: mode == settings.themeMode
                                  ? scheme.onPrimary
                                  : context.tokens.muted,
                            ),
                            child: Text(label),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final color in AppPalette.accentColors)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Pressable(
                onTap: () => settings.setAccent(color),
                scale: 0.85,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == settings.accent
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: color == settings.accent
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: color == settings.accent
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 预设颜色选择器（休息日/请假等日历标记色）。
class _PresetColorPicker extends StatelessWidget {
  const _PresetColorPicker({
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final color in colors)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Pressable(
                onTap: () => onSelect(color),
                scale: 0.85,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color == selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: color == selected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: color == selected
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 通用金额输入弹窗，返回输入值（取消/非法为 null）。
Future<double?> _editAmount(
  BuildContext context, {
  required String title,
  required String hint,
  required String suffix,
  required double initial,
  int maxIntegerDigits = 6,
}) async {
  final controller = TextEditingController(
    text: initial == initial.roundToDouble()
        ? initial.toInt().toString()
        : initial.toString(),
  );
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp('^\\d{0,$maxIntegerDigits}\\.?\\d{0,2}'),
          ),
        ],
        decoration: InputDecoration(hintText: hint, suffixText: suffix),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return double.tryParse(result ?? '');
}

Future<void> _editJobName(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  final controller = TextEditingController(text: job.name);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('工作名称'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 12,
        decoration: const InputDecoration(hintText: '输入工作名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final name = result?.trim();
  if (name != null && name.isNotEmpty) {
    await settings.updateJob(job.copyWith(name: name));
  }
}

Future<void> _editJobRate(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  final (title, hint, suffix, value, digits) = switch (job.calcMode) {
    CalcMode.hourly => (
      '设置时薪',
      '输入每小时工资',
      '${settings.currency}/小时',
      job.hourlyRate,
      6,
    ),
    CalcMode.fixedDaily => (
      '设置日薪',
      '输入每天固定工资',
      '${settings.currency}/天',
      job.dailyWage,
      7,
    ),
    CalcMode.monthly => (
      '设置月薪',
      '每月固定工资',
      '${settings.currency}/月',
      job.monthlySalary,
      8,
    ),
  };
  final input = await _editAmount(
    context,
    title: title,
    hint: hint,
    suffix: suffix,
    initial: value,
    maxIntegerDigits: digits,
  );
  if (input == null || input <= 0) return;
  await settings.updateJob(switch (job.calcMode) {
    CalcMode.hourly => job.copyWith(hourlyRate: input),
    CalcMode.fixedDaily => job.copyWith(dailyWage: input),
    CalcMode.monthly => job.copyWith(monthlySalary: input),
  });
}

Future<void> _editOvertimeRate(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  final input = await _editAmount(
    context,
    title: '设置加班时薪',
    hint: '加班每小时收入',
    suffix: '${settings.currency}/小时',
    initial: job.overtimeRate,
    maxIntegerDigits: 7,
  );
  if (input != null && input > 0) {
    await settings.updateJob(job.copyWith(overtimeRate: input));
  }
}

Future<void> _editTaxRate(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  final controller = TextEditingController(text: _trim(job.taxRate * 100));
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设置税率'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d{0,2}')),
        ],
        decoration: const InputDecoration(hintText: '输入税率百分数', suffixText: '%'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final value = double.tryParse(result ?? '');
  if (value != null && value > 0 && value < 100) {
    await settings.updateJob(job.copyWith(taxRate: value / 100));
  }
}

Future<void> _editTaxThreshold(
  BuildContext context,
  SettingsController settings,
  Job job,
) async {
  final controller = TextEditingController(text: _trim(job.taxThreshold));
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设置起征点'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d{0,8}\.?\d{0,2}')),
        ],
        decoration: InputDecoration(
          hintText: '每月免征额度',
          suffixText: '${settings.currency}/月',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final value = double.tryParse(result ?? '');
  if (value != null && value >= 0) {
    await settings.updateJob(job.copyWith(taxThreshold: value));
  }
}

Future<void> _pickCurrency(
  BuildContext context,
  SettingsController settings,
) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 14),
              child: Text(
                '货币符号',
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: context.colors.onSurface,
                ),
              ),
            ),
            for (final (symbol, name) in [
              ('¥', '人民币'),
              (r'$', '美元'),
              ('€', '欧元'),
              ('£', '英镑'),
            ])
              ListTile(
                leading: SizedBox(
                  width: 40,
                  child: Text(
                    symbol,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.colors.primary,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: symbol == settings.currency
                    ? Icon(
                        LucideIcons.check,
                        size: 20,
                        color: context.colors.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(context, symbol),
              ),
          ],
        ),
      ),
    ),
  );
  if (result != null && result.isNotEmpty) {
    await settings.setCurrency(result);
  }
}

/// 分钟数 → HH:mm。
String _timeLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 选择上班/下班时刻（按工作配置）。
Future<void> _pickWorkTime(
  BuildContext context,
  SettingsController settings,
  Job job, {
  required bool isStart,
}) async {
  final current = isStart ? job.workStart : job.workEnd;
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    helpText: isStart ? '选择上班时间' : '选择下班时间',
  );
  if (picked == null) return;
  final minutes = picked.hour * 60 + picked.minute;
  await settings.updateJob(
    isStart ? job.copyWith(workStart: minutes) : job.copyWith(workEnd: minutes),
  );
}

/// 删除工作：连同其全部记录一起删除。
Future<void> _deleteJob(
  BuildContext context,
  SettingsController settings,
  RecordsController records,
  Job job,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('删除「${job.name}」'),
      content: Text('该工作的打卡、标记、加班与提成记录将一并删除，且无法恢复。确定继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('删除', style: TextStyle(color: context.tokens.danger)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await records.removeJob(job.id);
    await settings.removeJob(job.id);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}

/// 导出备份：全部 xinji.* 键值打包为 JSON 文件并分享。
Future<void> _exportBackup(BuildContext context) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
    final backup = {
      'app': 'xinji',
      'format': 1,
      'exportedAt': now.toIso8601String(),
      'prefs': {
        for (final k in prefs.getKeys())
          if (k.startsWith('xinji.')) k: prefs.get(k),
      },
    };
    final json = const JsonEncoder.withIndent('  ').convert(backup);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/xinji-backup-$stamp.json');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)], text: '薪迹数据备份 $stamp');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    }
  }
}

/// 导入备份：选择 JSON 文件，确认后覆盖写回并重新加载。
Future<void> _importBackup(
  BuildContext context, {
  required SettingsController settings,
  required RecordsController records,
}) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (picked == null) return;
  final path = picked.files.single.path;
  if (path == null) return;

  Map<String, dynamic> backup;
  try {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != 'xinji' ||
        decoded['prefs'] is! Map) {
      throw const FormatException('不是薪迹备份文件');
    }
    backup = decoded;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导入失败：不是有效的薪迹备份文件')));
    }
    return;
  }

  final entries = (backup['prefs'] as Map).entries.where((e) {
    return e.key is String &&
        (e.value is String ||
            e.value is bool ||
            e.value is int ||
            e.value is double);
  }).length;
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('导入备份？'),
      content: Text('备份共 $entries 项数据，导入将覆盖当前所有设置与记录，此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final prefs = await SharedPreferences.getInstance();
  for (final e in (backup['prefs'] as Map).entries) {
    if (e.key is! String) continue;
    final key = e.key as String;
    final value = e.value;
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }
  await settings.reload();
  await records.reload();
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('导入成功')));
  }
}

Future<void> _clearAll(BuildContext context, RecordsController records) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清空所有记录'),
      content: const Text('所有工资记录将被永久删除，且无法恢复。确定继续吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('清空', style: TextStyle(color: context.tokens.danger)),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await records.clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清空所有记录')));
    }
  }
}
