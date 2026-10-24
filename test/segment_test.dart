import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/records/state/earnings.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

/// 分段口径（开关仅今后生效 / 同步历史）测试。
void main() {
  test('分段开关：仅今后生效 → 历史日期保持原口径，今天起按新值', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final job = s.jobs.first;

    // 个税：false → true，仅今后
    final switched = job.copyWithSwitch(
      JobSwitch.tax,
      true,
      fromNowOnly: true,
    );
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    expect(switched.taxEnabled, isTrue);
    expect(switched.effectiveTaxEnabled(yesterday), isFalse);
    expect(switched.effectiveTaxEnabled(today), isTrue);
    expect(switched.hasSwitchHistory, isTrue);
  });

  test('分段开关：同步当月保留之前各段（多月口径互不覆盖）', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final now = DateTime.now();
    final lastMonthMid = DateTime(now.year, now.month - 1, 15);
    final lastMonthEarly = DateTime(now.year, now.month - 1, 5);

    // 显式构造多段历史：9 月前 true，上月 15 日 false，当前 false
    final job = s.jobs.first.copyWith(
      taxEnabled: false,
      taxHistory: [
        (from: '', value: true),
        (from: dayKeyOf(lastMonthMid), value: false),
      ],
    );

    // 同步当月开启：本月整月 true，之前各段原样保留
    final synced = job.copyWithSwitch(JobSwitch.tax, true, fromNowOnly: false);
    expect(synced.effectiveTaxEnabled(lastMonthEarly), isTrue); // 早期段
    expect(synced.effectiveTaxEnabled(lastMonthMid), isFalse); // 上月中段保持
    expect(synced.effectiveTaxEnabled(now), isTrue); // 本月新值
    expect(
      synced.effectiveTaxEnabled(DateTime(now.year, now.month, 1)),
      isTrue,
    ); // 本月月初即新值
    expect(synced.taxHistory.length, 3);
    expect(synced.taxHistory.last.from, dayKeyOf(DateTime(now.year, now.month)));
  });

  test('分段开关：加班费历史保持计费、今天起不计费（收入按日分段计算）', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final records = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final now = DateTime.now();
    // 上月 15 日：永不与「今天/当月」混淆，验证同步当月不影响历史月份
    final historyDay = DateTime(now.year, now.month - 1, 15);
    final job = settings.activeJob!;

    // 两天各：12h 打卡 + 1h 手动加班（时薪 20、加班时薪 30）
    for (final d in [historyDay, now]) {
      await records.addPunchAt(true, DateTime(d.year, d.month, d.day, 9, 0));
      await records.addPunchAt(false, DateTime(d.year, d.month, d.day, 21, 0));
      await records.setOvertime(dayKeyOf(d), 1);
    }

    // 关闭加班费，仅今后生效
    await settings.updateJob(
      job.copyWithSwitch(JobSwitch.overtimePaid, false, fromNowOnly: true),
    );

    // 历史日：加班照常计费（240 + 30）
    expect(
      earningsOf(settings, records, start: historyDay, end: historyDay),
      270,
    );
    // 今天：加班不计费（240）
    expect(earningsOf(settings, records, start: now, end: now), 240);

    // 同步当月后：本月整月不计加班费，上月保持原口径不受影响
    await settings.updateJob(
      settings.activeJob!.copyWithSwitch(
        JobSwitch.overtimePaid,
        false,
        fromNowOnly: false,
      ),
    );
    // 上月（历史月份）：同步当月不改写，加班费照常计
    expect(
      earningsOf(settings, records, start: historyDay, end: historyDay),
      270,
    );
    // 今天（当月）：新口径生效，加班不计费
    expect(earningsOf(settings, records, start: now, end: now), 240);
  });

  test('分段开关：个税按月判定 + JSON 往返持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final job = s.jobs.first;
    final now = DateTime.now();

    // 关闭个税 → 开启，仅今后生效
    final switched = job.copyWithSwitch(
      JobSwitch.tax,
      true,
      fromNowOnly: true,
    );
    // 切换当月：今天生效 → 整月计税
    expect(taxEffectiveInMonth(switched, DateTime(now.year, now.month)), isTrue);
    // 上月：全月未生效 → 不计税
    expect(
      taxEffectiveInMonth(switched, DateTime(now.year, now.month - 1)),
      isFalse,
    );

    // JSON 往返：分段历史持久化
    final restored = Job.fromJson(switched.toJson());
    expect(restored.hasSwitchHistory, isTrue);
    expect(restored.taxEnabled, isTrue);
    expect(restored.effectiveTaxEnabled(now), isTrue);
    expect(
      restored.effectiveTaxEnabled(DateTime(now.year, now.month, now.day - 1)),
      isFalse,
    );

    // 个税关闭：当月一起关闭（整月不计税）——无论此前当月是否计过
    final closed = switched.copyWithSwitch(
      JobSwitch.tax,
      false,
      fromNowOnly: false,
    );
    expect(
      taxEffectiveInMonth(closed, DateTime(now.year, now.month)),
      isFalse,
    );
    // 上月保持当时的口径（未开启）
    expect(
      taxEffectiveInMonth(closed, DateTime(now.year, now.month - 1)),
      isFalse,
    );
  });
}
