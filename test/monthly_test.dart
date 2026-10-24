import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/records/data/day_mark.dart';
import 'package:xinji/features/records/state/earnings.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';
import 'package:xinji/features/statistics/pages/stats_page.dart';

/// 月薪「按实际天数折算」口径测试：分母为当月应出勤天数
///（当月天数 − 排班休息天数），排班休息日不扣钱。
void main() {
  test('月薪满勤：排班休息日不扣钱，出满应出勤天数即全额月薪', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final job = settings.activeJob!;
    await settings.updateJob(
      job.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5500,
        monthlyByActualDays: true,
        restMode: RestSchedule.fixed,
        fixedRestWeekdays: {DateTime.sunday},
      ),
    );

    // 2026 年 10 月：31 天，周日休息
    final monthStart = DateTime(2026, 10, 1);
    final monthEnd = DateTime(2026, 10, 31);
    var expectedWorkdays = 0;
    for (var d = monthStart;
        !d.isAfter(monthEnd);
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday != DateTime.sunday) {
        expectedWorkdays++;
        await records.setMark(dayKeyOf(d), DayMark.work(9), jobId: job.id);
      }
    }

    // 满勤：全额 5500（修复前误按 27/31 折算为 4790.32）
    expect(
      earningsOf(settings, records, start: monthStart, end: monthEnd),
      closeTo(5500, 0.01),
    );

    // 少出勤 1 天：按 1/应出勤天数 扣钱
    await records.setMark(dayKeyOf(monthEnd), null, jobId: job.id);
    expect(
      earningsOf(settings, records, start: monthStart, end: monthEnd),
      closeTo(5500 * (expectedWorkdays - 1) / expectedWorkdays, 0.01),
    );
  });

  test('月薪手动休息（节假日）：从应出勤分母扣除，当月仍拿全工资', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final job = settings.activeJob!;
    await settings.updateJob(
      job.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5500,
        monthlyByActualDays: true,
        restMode: RestSchedule.fixed,
        fixedRestWeekdays: {DateTime.sunday},
      ),
    );

    // 2026 年 10 月：周日排班休；再把 10-01 ~ 10-03 手动标记为节假日休息
    final monthStart = DateTime(2026, 10, 1);
    final monthEnd = DateTime(2026, 10, 31);
    var workdays = 0;
    for (var d = monthStart;
        !d.isAfter(monthEnd);
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday == DateTime.sunday) continue;
      if (d.day <= 3) {
        await records.setMark(dayKeyOf(d), const DayMark.rest(), jobId: job.id);
        continue;
      }
      workdays++;
      await records.setMark(dayKeyOf(d), DayMark.work(9), jobId: job.id);
    }

    // 手动休息 3 天从分母扣除：出勤 workdays / 应出勤 workdays → 全额
    expect(workdays, 24); // 27 − 3 个手动休息日
    expect(
      earningsOf(settings, records, start: monthStart, end: monthEnd),
      closeTo(5500, 0.01),
    );

    // 请假 1 天：分母不减（仍按应出勤折算），按比例扣钱
    await records.setMark(
      dayKeyOf(DateTime(2026, 10, 31)),
      const DayMark.leave(),
      jobId: job.id,
    );
    expect(
      earningsOf(settings, records, start: monthStart, end: monthEnd),
      closeTo(5500 * 23 / 24, 0.01),
    );
  });

  test('月薪无固定排班：分母为当月总天数（休息/未打卡按比例扣）', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final job = settings.activeJob!;
    await settings.updateJob(
      job.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5500,
        monthlyByActualDays: true,
        restMode: RestSchedule.flexible,
      ),
    );

    // 2026 年 10 月共 31 天，仅出勤 27 天（前 27 天标记工作）
    final monthStart = DateTime(2026, 10, 1);
    final monthEnd = DateTime(2026, 10, 31);
    for (var d = monthStart;
        !d.isAfter(DateTime(2026, 10, 27));
        d = DateTime(d.year, d.month, d.day + 1)) {
      await records.setMark(dayKeyOf(d), DayMark.work(9), jobId: job.id);
    }

    expect(
      earningsOf(settings, records, start: monthStart, end: monthEnd),
      closeTo(5500 * 27 / 31, 0.01),
    );
  });

  test('统计锚点周期：个税开关关闭时不扣税（回归，曾无条件计税）', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final job = settings.activeJob!;
    await settings.updateJob(
      job.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5500,
        monthlyByActualDays: true,
        restMode: RestSchedule.fixed,
        fixedRestWeekdays: {DateTime.sunday},
        taxEnabled: false,
      ),
    );

    // 2026 年 10 月：非周日全部标记工作（满勤 27 天）
    for (var d = DateTime(2026, 10, 1);
        !d.isAfter(DateTime(2026, 10, 31));
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday == DateTime.sunday) continue;
      await records.setMark(dayKeyOf(d), DayMark.work(9), jobId: job.id);
    }

    final r = netEarningsOfAnchorPeriod(
      settings,
      records,
      DateTime(2026, 10),
      DateTime(2026, 10),
      jobId: job.id,
    );
    // 关闭个税：不扣税，满勤全额（修复前误扣 15 显示 5485）
    expect(r.net, closeTo(5500, 0.01));
    expect(r.tax, 0);
  });

  test('今日税后收入：开启个税时按今日收入占比分摊本月个税', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final job = settings.activeJob!;
    await settings.updateJob(
      job.copyWith(
        calcMode: CalcMode.monthly,
        monthlySalary: 5500,
        monthlyByActualDays: true,
        restMode: RestSchedule.fixed,
        fixedRestWeekdays: {DateTime.sunday},
        taxEnabled: true,
        taxThreshold: 5000,
        taxRate: 0.03,
      ),
    );

    // 2026 年 10 月：非周日全部标记工作（满勤 27 天）
    for (var d = DateTime(2026, 10, 1);
        !d.isAfter(DateTime(2026, 10, 31));
        d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday == DateTime.sunday) continue;
      await records.setMark(dayKeyOf(d), DayMark.work(9), jobId: job.id);
    }

    // 月税 = (5500-5000)×3% = 15；10-20（周二）税前 5500/27
    final day = DateTime(2026, 10, 20);
    final dayGross = 5500 / 27;
    expect(
      netEarningsOfDay(settings, records, day, jobId: job.id),
      closeTo(dayGross * (1 - 15 / 5500), 0.01),
    );

    // 关闭个税后：今日税后 = 税前（不扣）
    await settings.updateJob(
      settings.activeJob!.copyWithSwitch(JobSwitch.tax, false, fromNowOnly: false),
    );
    expect(
      netEarningsOfDay(settings, records, day, jobId: job.id),
      closeTo(dayGross, 0.01),
    );
  });
}
