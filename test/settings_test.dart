import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/features/records/data/day_mark.dart';
import 'package:xinji/features/records/state/earnings.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

void main() {
  test('设置：外观（休息日颜色/请假颜色/日历工时显示/底栏样式）持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s.loaded, true);

    // 默认值
    expect(s.calendarShowsHours, false);
    expect(s.navBarLabels, false);
    expect(s.navBarCircle, false);

    // 修改
    await s.setCalendarShowsHours(true);
    await s.setNavBarLabels(true);
    await s.setNavBarCircle(true);

    // 重新加载后保持
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.calendarShowsHours, true);
    expect(s2.navBarLabels, true);
    expect(s2.navBarCircle, true);
  });

  test('设置：主题模式持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s.themeMode, ThemeMode.system);

    await s.setThemeMode(ThemeMode.dark);
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.themeMode, ThemeMode.dark);
  });

  test('工作：跨天分割与打卡模式为每工作独立设置并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final job = s.jobs.first;
    // 默认：分割 + 精准
    expect(job.splitOvernight, true);
    expect(job.punchMode, 2);

    await s.updateJob(job.copyWith(splitOvernight: false, punchMode: 1));
    // 新增的第二份工作仍为默认值（互相独立）
    final job2 = await s.addJob();
    expect(job2.splitOvernight, true);
    expect(job2.punchMode, 2);

    // 重新加载后各自保持
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.first.splitOvernight, false);
    expect(s2.jobs.first.punchMode, 1);
    expect(s2.jobs.last.splitOvernight, true);
    expect(s2.jobs.last.punchMode, 2);
  });

  test('工作：打卡提醒时间点（多时间、迁移、持久化）', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    // 默认：关闭、无时间点
    expect(s.jobs.first.punchReminders, false);
    expect(s.jobs.first.reminderMinutes, isEmpty);

    // 添加多个提醒时间并开启
    await s.updateJob(
      s.activeJob!.copyWith(
        punchReminders: true,
        reminderMinutes: [1080, 540, 780],
      ),
    );
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.first.punchReminders, true);
    // 加载时排序去重，保证多来源数据（导入/旧版本）顺序稳定
    expect(s2.jobs.first.reminderMinutes, [540, 780, 1080]);

    // 旧数据迁移：JSON 无 reminderMinutes 但开关开启 → 沿用上下班时间
    final legacy = Job.fromJson({
      ...s2.jobs.first.toJson()..remove('reminderMinutes'),
      'id': 'legacy',
      'name': '旧数据',
      'workStart': 600,
      'workEnd': 1200,
    });
    expect(legacy.reminderMinutes, [600, 1200]);
    // 开关关闭的旧数据：空列表
    final legacyOff = Job.fromJson({
      ...legacy.toJson(),
      'id': 'legacy2',
      'punchReminders': false,
    }..remove('reminderMinutes'));
    expect(legacyOff.reminderMinutes, isEmpty);
  });

  test('工作：今日页标签（显示与顺序）持久化且旧数据回落默认', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    // 默认全部显示，顺序：工时/加班/薪资/个税
    expect(s.jobs.first.heroTags, kDefaultHeroTags);

    // 隐藏「加班」并调整顺序：薪资 → 工时 → 个税
    await s.updateJob(
      s.activeJob!.copyWith(heroTags: ['rate', 'hours', 'tax']),
    );
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.first.heroTags, ['rate', 'hours', 'tax']);

    // 旧 JSON 无 heroTags 字段：回落默认；未知值被过滤
    final s3 = SettingsController();
    await Future.delayed(Duration.zero);
    final job = s3.jobs.first;
    final restored = Job.fromJson({
      ...job.toJson()..remove('heroTags'),
      'id': 'jx',
      'name': '旧数据',
    });
    expect(restored.heroTags, kDefaultHeroTags);
    final dirty = Job.fromJson({
      ...job.toJson(),
      'id': 'jy',
      'name': '脏数据',
      'heroTags': ['tax', 'unknown', 'hours'],
    });
    expect(dirty.heroTags, ['tax', 'hours']);
  });

  test('迁移：旧版全局跨天分割/打卡模式/打卡提醒/个税一次性应用到全部工作', () async {
    SharedPreferences.setMockInitialValues({
      'xinji.splitOvernight': false,
      'xinji.punchMode': 1,
      'xinji.punchReminders': true,
      'xinji.taxEnabled': true,
      'xinji.taxThreshold': 8000,
      'xinji.taxRate': 0.1,
    });
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final job = s.jobs.first;
    expect(job.splitOvernight, false);
    expect(job.punchMode, 1);
    expect(job.punchReminders, true);
    expect(job.taxEnabled, true);
    expect(job.taxThreshold, 8000);
    expect(job.taxRate, 0.1);

    // 旧全局键已清除：之后的 per-job 修改不会被旧值覆盖
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('xinji.splitOvernight'), isNull);
    expect(prefs.getInt('xinji.punchMode'), isNull);
    expect(prefs.getBool('xinji.punchReminders'), isNull);
    expect(prefs.getBool('xinji.taxEnabled'), isNull);
    expect(prefs.getDouble('xinji.taxThreshold'), isNull);
    expect(prefs.getDouble('xinji.taxRate'), isNull);

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.first.splitOvernight, false);
    await s2.updateJob(s2.jobs.first.copyWith(splitOvernight: true));
    final s3 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s3.jobs.first.splitOvernight, true);
    expect(s3.jobs.first.taxEnabled, true);
  });

  test('设置：统计周期锚点持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    // 默认：周一起始、每月 1 号、每年 1 月 1 日、累计全部
    expect(s.statsWeekStart, 1);
    expect(s.statsMonthAnchorDay, 1);
    expect(s.statsYearAnchorMonth, 1);
    expect(s.statsYearAnchorDay, 1);
    expect(s.statsTotalStart, isNull);

    await s.setStatsWeekStart(3);
    await s.setStatsMonthAnchorDay(15);
    await s.setStatsYearAnchor(3, 1);
    await s.setStatsTotalStart(DateTime(2026, 10, 1));

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.statsWeekStart, 3);
    expect(s2.statsMonthAnchorDay, 15);
    expect(s2.statsYearAnchorMonth, 3);
    expect(s2.statsYearAnchorDay, 1);
    expect(s2.statsTotalStart, DateTime(2026, 10, 1));

    await s2.setStatsTotalStart(null);
    final s3 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s3.statsTotalStart, isNull);
  });

  test('工作：旧版全局薪资设置自动迁移为默认工作', () async {
    SharedPreferences.setMockInitialValues({
      // 旧版全局键
      'xinji.calcMode': 2, // 月薪
      'xinji.monthlySalary': 8000.0,
      'xinji.monthlyByActualDays': true,
      'xinji.overtimeRate': 40.0,
      'xinji.workStart': 600,
      'xinji.workEnd': 1200,
      'xinji.restMode': 1, // 固定休息
      'xinji.fixedRest': '[1,7]',
    });
    final s = SettingsController();
    await Future.delayed(Duration.zero);

    expect(s.jobs.length, 1);
    final job = s.jobs.first;
    expect(job.id, 'job1');
    expect(job.name, '默认工作');
    expect(job.calcMode, CalcMode.monthly);
    expect(job.monthlySalary, 8000);
    expect(job.monthlyByActualDays, true);
    expect(job.overtimeRate, 40);
    expect(job.workStart, 600);
    expect(job.workEnd, 1200);
    expect(job.restMode, RestSchedule.fixed);
    expect(job.fixedRestWeekdays, {1, 7});
    // 标准工时 = 1200-600 分钟
    expect(job.standardWorkMinutes, 600);
    expect(s.activeJobId, 'job1');

    // 重新加载：迁移结果已持久化
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.length, 1);
    expect(s2.jobs.first.id, 'job1');
    expect(s2.jobs.first.monthlySalary, 8000);
  });

  test('工作：新增/更新/删除与选中回退', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s.jobs.length, 1);

    // 新增
    final job2 = await s.addJob();
    expect(s.jobs.length, 2);
    expect(s.activeJobId, job2.id);

    // 更新（改名 + 改薪资方式）
    await s.updateJob(job2.copyWith(name: '周末兼职', dailyWage: 150));
    expect(s.jobById(job2.id)!.name, '周末兼职');
    expect(s.jobById(job2.id)!.dailyWage, 150);

    // 重新加载后保持
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.length, 2);
    expect(s2.jobById(job2.id)!.name, '周末兼职');
    expect(s2.activeJobId, job2.id);

    // 删除当前选中工作：选中回退到第一份
    await s2.removeJob(job2.id);
    expect(s2.jobs.length, 1);
    expect(s2.activeJobId, 'job1');

    // 不允许删除最后一份工作
    await s2.removeJob('job1');
    expect(s2.jobs.length, 1);
  });

  test('工作：薪资方式与各金额持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final job = s.activeJob!;

    await s.updateJob(
      job.copyWith(
        calcMode: CalcMode.fixedDaily,
        dailyWage: 260,
        overtimeRate: 45,
      ),
    );
    expect(s.activeJob!.calcMode, CalcMode.fixedDaily);
    expect(s.activeJob!.dailyWage, 260);

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.activeJob!.calcMode, CalcMode.fixedDaily);
    expect(s2.activeJob!.dailyWage, 260);
    expect(s2.activeJob!.overtimeRate, 45);
  });

  test('工作：上下班时间持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    await s.updateJob(s.activeJob!.copyWith(workStart: 600, workEnd: 1200));
    expect(s.activeJob!.workStart, 600);
    expect(s.activeJob!.workEnd, 1200);
    expect(s.activeJob!.standardWorkMinutes, 600);

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.activeJob!.workStart, 600);
    expect(s2.activeJob!.workEnd, 1200);
  });

  test('工作：休息日排班持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final job = s.activeJob!;

    // 默认无固定休息
    expect(job.restMode, RestSchedule.flexible);
    final someday = DateTime(2026, 10, 24); // 周六
    expect(job.isScheduledRest(someday), false);

    // 固定休息：周六日
    await s.updateJob(
      job.copyWith(
        restMode: RestSchedule.fixed,
        fixedRestWeekdays: {DateTime.saturday, DateTime.sunday},
      ),
    );
    final fixed = s.activeJob!;
    expect(fixed.isScheduledRest(someday), true);
    expect(fixed.isScheduledRest(DateTime(2026, 10, 26)), false); // 周一
    // 全部工作均为排班休息日
    expect(s.isScheduledRestAll(someday), true);

    // 重新加载后保持
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.activeJob!.restMode, RestSchedule.fixed);
    expect(s2.activeJob!.fixedRestWeekdays, {
      DateTime.saturday,
      DateTime.sunday,
    });
    expect(s2.activeJob!.isScheduledRest(someday), true);
  });

  test('设置：统计组件排序与显示持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s.statsOrder, StatsSection.values);

    // 隐藏月历，调整顺序
    await s.setStatsSectionVisible(StatsSection.calendar, false);
    await s.setStatsOrder([
      StatsSection.total,
      StatsSection.monthly,
      StatsSection.periods,
    ]);
    expect(s.visibleStatsSections, [
      StatsSection.total,
      StatsSection.monthly,
      StatsSection.periods,
      StatsSection.daily,
    ]);

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.visibleStatsSections, [
      StatsSection.total,
      StatsSection.monthly,
      StatsSection.periods,
      StatsSection.daily,
    ]);
  });

  test('工作：标识色迁移补齐/轮选/持久化', () async {
    SharedPreferences.setMockInitialValues({
      // 旧版多工作数据：无 colorIndex 字段
      'xinji.jobs': jsonEncode([
        {'id': 'job1', 'name': '主职', 'calcMode': 0, 'hourlyRate': 20},
        {'id': 'job2', 'name': '周末兼职', 'calcMode': 1, 'dailyWage': 150},
      ]),
    });
    final s = SettingsController();
    await Future.delayed(Duration.zero);

    // 旧数据无标识色：按位置轮选补齐并立即持久化
    expect(s.jobs[0].colorIndex, 0);
    expect(s.jobs[1].colorIndex, 1);
    expect(s.jobs[1].color, AppPalette.jobColors[1]);

    // 新增工作：选首个未用颜色
    final job3 = await s.addJob();
    expect(s.jobById(job3.id)!.colorIndex, 2);

    // 修改标识色后重新加载保持
    await s.updateJob(s.jobs[0].copyWith(colorIndex: 5));
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs[0].colorIndex, 5);
    expect(s2.jobById(job3.id)!.colorIndex, 2);
  });

  test('新增工作草稿：点完成才保存，中途取消则丢弃', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);

    final job = s.createDraftJob();
    expect(s.jobs.length, 2); // 默认工作 + 草稿

    // 草稿期间的修改不持久化
    await s.updateJob(job.copyWith(name: '夜班兼职'));
    final probe = SettingsController();
    await Future.delayed(Duration.zero);
    expect(probe.jobs.any((j) => j.name == '夜班兼职'), isFalse);

    // 取消：丢弃草稿
    s.discardDraftJob();
    expect(s.jobs.length, 1);

    // 重新创建并点「完成」：持久化保存
    final job2 = s.createDraftJob();
    await s.updateJob(job2.copyWith(name: '夜班兼职'));
    await s.commitDraftJob();
    final probe2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(probe2.jobs.any((j) => j.name == '夜班兼职'), isTrue);
    expect(probe2.jobs.length, 2);
  });

  test('设置：个税按工作独立计算（近似）', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    // 默认工作设为日薪 200，标记一个工作日
    final job1 = s.activeJob!;
    await s.updateJob(
      job1.copyWith(calcMode: CalcMode.fixedDaily, dailyWage: 200),
    );
    await records.setMark('2026-10-15', const DayMark.work(0));

    // 记提成
    await records.setCommission(DateTime(2026, 10, 15), 1000);
    expect(records.commissionTotal, 1000);

    // 开启个税：起征 5000，税率 10%
    await s.updateJob(
      s.activeJob!.copyWith(taxEnabled: true, taxThreshold: 5000, taxRate: 0.1),
    );

    // 10 月税前 = 200(工资) + 1000(提成) = 1200，未超起征点，税为 0
    var net = netEarningsOfMonth(s, records, DateTime(2026, 10));
    expect(net, 1200);

    // 起征点降为 1000：应税 200，税 20，到手 1180
    await s.updateJob(s.activeJob!.copyWith(taxThreshold: 1000));
    net = netEarningsOfMonth(s, records, DateTime(2026, 10));
    expect(net, 1180);

    // 提成改为 6000：税前 6200，应税 5200，税 520，到手 5680
    await records.setCommission(DateTime(2026, 10, 15), 6000);
    net = netEarningsOfMonth(s, records, DateTime(2026, 10));
    expect(net, 5680);

    // 新增第二份工作（未开个税）：全部口径下第二份不计税
    final job2 = await s.addJob();
    await s.updateJob(
      job2.copyWith(calcMode: CalcMode.fixedDaily, dailyWage: 200),
    );
    await records.setMark('2026-10-16', const DayMark.work(0), jobId: job2.id);
    // 全部税前 = 6200 + 200 = 6400；job1 税 520，job2 无税 → 到手 5880
    net = netEarningsOfMonth(s, records, DateTime(2026, 10));
    expect(net, 5880);
    // 单看 job2：无税
    expect(
      netEarningsOfMonth(s, records, DateTime(2026, 10), jobId: job2.id),
      200,
    );
  });

  test('多工作：收入按各工作参数独立计算', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    // 默认工作：时薪 20，打 2 小时卡
    await records.addPunchAt(true, DateTime(2026, 10, 15, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 15, 11));

    // 第二份工作：日薪 200，标记一个工作日
    final job2 = await s.addJob();
    await s.updateJob(
      job2.copyWith(calcMode: CalcMode.fixedDaily, dailyWage: 200),
    );
    await records.setMark('2026-10-16', const DayMark.work(0), jobId: job2.id);

    // 全部 = 2h×20 + 1天×200 = 240
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 16),
      ),
      240,
    );
    // 单看第二份工作 = 200
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 16),
        jobId: job2.id,
      ),
      200,
    );
    // 第一份工作（job1）打卡默认归入
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      40,
    );

    // 删除第二份工作：其记录一并清除
    await records.removeJob(job2.id);
    await s.removeJob(job2.id);
    expect(records.markOf('2026-10-16'), isNull);
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 16),
      ),
      40,
    );
  });

  test('自动加班（时薪）：超出标准工时部分按加班时薪计，不重复计薪', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    // 时薪 20、加班时薪 30、上下班 09:00-18:00（标准 9 小时）
    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.hourly,
        hourlyRate: 20,
        overtimeRate: 30,
        autoOvertime: true,
      ),
    );

    // 10-15 打卡 09:00 → 21:00，共 12 小时
    await records.addPunchAt(true, DateTime(2026, 10, 15, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 15, 21));
    // 10-16 打卡 09:00 → 17:00，共 8 小时（未超标准）
    await records.addPunchAt(true, DateTime(2026, 10, 16, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 16, 17));

    expect(records.autoOvertimeOf('2026-10-15', 540), 3.0);
    expect(records.autoOvertimeOf('2026-10-16', 540), 0.0);
    expect(records.autoOvertimeHours(540), 3.0);
    expect(
      records.autoOvertimeHours(
        540,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      3.0,
    );
    expect(
      records.autoOvertimeHours(
        540,
        start: DateTime(2026, 10, 16),
        end: DateTime(2026, 10, 16),
      ),
      0.0,
    );

    // 10-15：9h × 20 + 3h × 30 = 270（而非整段按时薪 240）
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      270,
    );
    // 全部：10-15 270 + 10-16 8h×20=160 → 430
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 16),
      ),
      430,
    );
  });

  test('自动加班（日薪/月薪）：底薪不动，超出部分只加加班费', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    // 日薪 200、加班时薪 30、标准 9 小时
    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.fixedDaily,
        dailyWage: 200,
        overtimeRate: 30,
        autoOvertime: true,
      ),
    );

    // 打卡 12 小时：1 天 × 200 + 3h × 30 = 290
    await records.addPunchAt(true, DateTime(2026, 10, 15, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 15, 21));
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      290,
    );

    // 月薪 5000（÷21.75）：1 天折算 + 3h × 30
    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5000,
        overtimeRate: 30,
      ),
    );
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      closeTo(5000 / 21.75 + 90, 1e-9),
    );
  });

  test('自动加班与手动加班相加互不重复', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.hourly,
        hourlyRate: 20,
        overtimeRate: 30,
        autoOvertime: true,
      ),
    );

    // 打卡 4h（未超标准）+ 手动加班 2h：4×20 + 2×30 = 140，自动加班 0
    await records.addPunchAt(true, DateTime(2026, 10, 15, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 15, 13));
    await records.setOvertime('2026-10-15', 2);
    expect(records.autoOvertimeOf('2026-10-15', 540), 0.0);
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      140,
    );

    // 打卡 12h + 手动加班 2h：基本 9×20 +（自动 3 + 手动 2）× 30 = 330
    await records.addPunchAt(true, DateTime(2026, 10, 16, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 16, 21));
    await records.setOvertime('2026-10-16', 2);
    expect(records.autoOvertimeOf('2026-10-16', 540), 3.0);
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 16),
        end: DateTime(2026, 10, 16),
      ),
      330,
    );
  });

  test('无加班费：加班工时照常统计但不增加金额', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);
    final records = RecordsController();
    await Future.delayed(Duration.zero);

    // 时薪 20、加班时薪 30、无加班费、自动加班开启
    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.hourly,
        hourlyRate: 20,
        overtimeRate: 30,
        autoOvertime: true,
        overtimePaid: false,
      ),
    );

    // 打卡 12h + 手动加班 2h：加班工时 5h 照常统计，
    // 但金额 = 全部基本工时 12h × 20 = 240（不拆分，手动加班也不计钱）
    await records.addPunchAt(true, DateTime(2026, 10, 15, 9));
    await records.addPunchAt(false, DateTime(2026, 10, 15, 21));
    await records.setOvertime('2026-10-15', 2);
    expect(records.autoOvertimeOf('2026-10-15', 540), 3.0);
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      240,
    );

    // 日薪 200、无加班费：打卡 12h → 只有 200，加班不计钱
    await s.updateJob(
      s.activeJob!.copyWith(calcMode: CalcMode.fixedDaily, dailyWage: 200),
    );
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      200,
    );

    // 关闭自动加班、无加班费、当天只剩手动加班 2h（移除打卡时段）：
    // 加班工时照常统计，但不增加金额 → 0
    await records.setOvertime('2026-10-15', 0);
    await records.setMark('2026-10-15', null);
    await records.undoLastSession();
    await records.setOvertime('2026-10-15', 2);
    await s.updateJob(
      s.activeJob!.copyWith(
        calcMode: CalcMode.hourly,
        hourlyRate: 20,
        autoOvertime: false,
      ),
    );
    expect(
      earningsOf(
        s,
        records,
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      0,
    );
    // 加班工时照常统计
    expect(
      records.overtimeHoursBetween(
        start: DateTime(2026, 10, 15),
        end: DateTime(2026, 10, 15),
      ),
      2,
    );
  });

  test('工作字段：autoOvertime/overtimePaid 持久化与旧数据兼容', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);

    // 默认值：不自动记加班、有加班费
    expect(s.activeJob!.autoOvertime, false);
    expect(s.activeJob!.overtimePaid, true);

    // 开启后保存
    await s.updateJob(
      s.activeJob!.copyWith(autoOvertime: true, overtimePaid: false),
    );
    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.activeJob!.autoOvertime, true);
    expect(s2.activeJob!.overtimePaid, false);

    // JSON round-trip
    final json = s2.activeJob!.toJson();
    expect(json['autoOvertime'], true);
    expect(json['overtimePaid'], false);

    // 旧数据（缺字段）：回落默认值
    final legacy = Map<String, dynamic>.from(json)
      ..remove('autoOvertime')
      ..remove('overtimePaid');
    final legacyJob = Job.fromJson(legacy);
    expect(legacyJob.autoOvertime, false);
    expect(legacyJob.overtimePaid, true);
  });

  test('设置：打卡提醒（每工作）与加班日颜色持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future.delayed(Duration.zero);

    // 默认：提醒关闭、颜色跟随主题（-1）
    expect(s.jobs.first.punchReminders, false);
    expect(s.overtimeColorIndex, -1);

    await s.updateJob(s.activeJob!.copyWith(punchReminders: true));
    await s.setOvertimeColorIndex(3);

    final s2 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s2.jobs.first.punchReminders, true);
    expect(s2.overtimeColorIndex, 3);

    // 越界索引不生效
    await s2.setOvertimeColorIndex(99);
    expect(s2.overtimeColorIndex, 3);

    // 切回默认
    await s2.setOvertimeColorIndex(-1);
    await s2.updateJob(s2.activeJob!.copyWith(punchReminders: false));
    final s3 = SettingsController();
    await Future.delayed(Duration.zero);
    expect(s3.jobs.first.punchReminders, false);
    expect(s3.overtimeColorIndex, -1);
  });
}
