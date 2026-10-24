import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/records/data/day_mark.dart';
import 'package:xinji/features/records/state/records_controller.dart';

void main() {
  test('打卡：多次上下班计算时段、总时长与撤销', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    // 等待 _load 完成
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(controller.loaded, isTrue);

    final key = dayKeyOf(DateTime(2026, 10, 23));
    expect(controller.isWorkingToday(key), isFalse);
    expect(controller.punchesOf(key), isEmpty);

    // 第一段：09:00 上班 → 12:00 下班 = 3 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 23, 9, 0));
    expect(controller.isWorkingToday(key), isTrue);
    await controller.addPunchAt(false, DateTime(2026, 10, 23, 12, 0));
    expect(controller.isWorkingToday(key), isFalse);
    expect(controller.totalWorkTime(key), const Duration(hours: 3));

    // 第二段：13:30 上班 → 18:00 下班 = 4.5 小时，累计 7.5 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 23, 13, 30));
    await controller.addPunchAt(false, DateTime(2026, 10, 23, 18, 0));
    expect(controller.sessionsOf(key).length, 2);
    expect(
      controller.totalWorkTime(key),
      const Duration(hours: 7, minutes: 30),
    );

    // 撤销最后一次打卡：回到上班中状态，仅剩第一段闭合时段（3 小时）
    await controller.undoLastPunch(key);
    expect(controller.isWorkingToday(key), isTrue);
    expect(controller.sessionsOf(key).length, 1);
    expect(controller.sessionsOf(key).first.duration, const Duration(hours: 3));

    // 打卡记录按时间排序
    expect(controller.punchesOf(key).length, 3);
    expect(controller.punchesOf(key).first.isIn, isTrue);
    expect(controller.punchesOf(key).last.isIn, isTrue);
  });

  test('打卡：数据持久化后可重新加载', () async {
    SharedPreferences.setMockInitialValues({});
    final first = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final key = dayKeyOf(DateTime(2026, 10, 23));
    await first.addPunchAt(true, DateTime(2026, 10, 23, 8, 30));
    await first.addPunchAt(false, DateTime(2026, 10, 23, 17, 45));

    // 新控制器实例应从存储中读回打卡数据
    final second = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(second.punchesOf(key).length, 2);
    expect(second.totalWorkTime(key), const Duration(hours: 9, minutes: 15));
  });

  test('打卡：清空数据同时清空打卡记录', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.addPunchAt(true, DateTime(2026, 10, 23, 9, 0));
    expect(controller.punches, isNotEmpty);

    await controller.clearAll();
    expect(controller.punches, isEmpty);
  });

  test('打卡工时换算：往日只算闭合时段，跨天/全量统计正确', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-22 完整一天：9:00-17:00 = 8 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 22, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 22, 17, 0));
    expect(controller.punchHoursOf('2026-10-22'), 8.0);

    // 10-21 忘记打下班卡（往日未闭合时段不算）
    await controller.addPunchAt(true, DateTime(2026, 10, 21, 9, 0));
    expect(controller.punchHoursOf('2026-10-21'), 0.0);

    // 全量 = 8 小时（只含闭合）
    expect(controller.hoursAll(), 8.0);

    // 时间范围统计
    expect(
      controller.hoursBetween(DateTime(2026, 10, 20), DateTime(2026, 10, 23)),
      8.0,
    );
    expect(
      controller.hoursBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 30)),
      0.0,
    );

    // 半小时精度：13:30-17:45 = 4.25 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 13, 30));
    await controller.addPunchAt(false, DateTime(2026, 10, 20, 17, 45));
    expect(controller.punchHoursOf('2026-10-20'), 4.25);
    expect(controller.hoursAll(), 12.25);

    // 出勤天数：3 天有打卡（10-20/21/22）
    expect(controller.workedDaysAll(), 3);
    expect(controller.hasPunchedOn('2026-10-20'), isTrue);
    expect(controller.hasPunchedOn('2026-10-19'), isFalse);
    expect(
      controller.workedDaysBetween(
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
      ),
      2,
    );
  });

  test('收入计算：时薪按工时、固定工资按出勤天数', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-22 干了一整天 8 小时；10-20 干了半天 2 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 22, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 22, 17, 0));
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 20, 11, 0));

    // 时薪模式：10 小时 × ¥30 = ¥300
    expect(controller.hoursEarnings(30), 300);
    expect(
      controller.hoursEarnings(
        30,
        start: DateTime(2026, 10, 22),
        end: DateTime(2026, 10, 22),
      ),
      240,
    );

    // 日薪模式（标准 09:00-18:00，半天阈值 4.5 小时）：
    // 10-22 打卡 8h → 整天；10-20 打卡 2h → 半天；合计 1.5 天 × ¥200 = ¥300
    expect(controller.fixedEarnings(200), 300);
    expect(
      controller.fixedEarnings(
        200,
        start: DateTime(2026, 10, 22),
        end: DateTime(2026, 10, 22),
      ),
      200,
    );

    // 空范围收入为 0
    expect(
      controller.hoursEarnings(
        30,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      ),
      0,
    );
    expect(
      controller.fixedEarnings(
        200,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      ),
      0,
    );
  });

  test('计薪天数：打卡与标记同日并存时打卡优先（与工时口径一致）', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    const standard = 540;

    // 休息标记 + 实际打卡 4h：计薪按打卡算半天（不再是标记的 0 天）
    await controller.setMark(
      dayKeyOf(DateTime(2026, 10, 21)),
      DayMark.rest(),
    );
    await controller.addPunchAt(true, DateTime(2026, 10, 21, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 13, 0));
    // 工作日标记 + 实际打卡 9.5h：按打卡算整天（与标记一致）
    await controller.setMark(
      dayKeyOf(DateTime(2026, 10, 22)),
      DayMark.work(0),
    );
    await controller.addPunchAt(true, DateTime(2026, 10, 22, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 22, 18, 30));
    // 仅标记无打卡：保持标记口径
    await controller.setMark(
      dayKeyOf(DateTime(2026, 10, 23)),
      DayMark.work(0),
    );

    expect(controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 21)), standard), 0.5);
    expect(controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 22)), standard), 1.0);
    expect(controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 23)), standard), 1.0);
    expect(controller.fixedEarnings(200, standardMinutes: standard), 500);
  });

  test('日薪/月薪：打完下班卡才计薪，按时长判断半天/整天', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 标准工时 09:00-18:00 = 540 分钟（半天阈值 270 分钟）
    const standard = 540;

    // 10-22 打卡 9.5h → 整天
    await controller.addPunchAt(true, DateTime(2026, 10, 22, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 22, 18, 30));
    // 10-21 打卡 4h（不足半个工时）→ 半天
    await controller.addPunchAt(true, DateTime(2026, 10, 21, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 13, 0));
    // 10-20 只打了上班卡（未闭合）→ 不计薪
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 9, 0));
    // 10-19 手工标记工作日 → 1 天
    await controller.setMark(dayKeyOf(DateTime(2026, 10, 19)), DayMark.work(0));

    expect(
      controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 22)), standard),
      1.0,
    );
    expect(
      controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 21)), standard),
      0.5,
    );
    expect(
      controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 20)), standard),
      0.0,
    );
    expect(
      controller.dayUnitsOf(dayKeyOf(DateTime(2026, 10, 19)), standard),
      1.0,
    );

    // 日薪 ¥200：1 + 0.5 + 0 + 1 = 2.5 天 → ¥500
    expect(controller.fixedEarnings(200, standardMinutes: standard), 500);
    // 未打下班卡的 10-20 单日 → ¥0
    expect(
      controller.fixedEarnings(
        200,
        start: DateTime(2026, 10, 20),
        end: DateTime(2026, 10, 20),
        standardMinutes: standard,
      ),
      0,
    );
    // 月薪 ÷ 21.75：2.5 天折算
    expect(
      controller.monthlyEarnings(5000, standardMinutes: standard),
      closeTo(5000 * 2.5 / 21.75, 0.001),
    );
    // 月薪按当月天数（10 月 31 天）逐日折算
    expect(
      controller.monthlyEarnings(
        5000,
        byActualDays: true,
        standardMinutes: standard,
      ),
      closeTo(5000 / 31 * 2.5, 0.001),
    );
  });

  test('日期标记：忘打卡补记工时、标记休息、打卡优先、持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-15 忘打卡，补记 8 小时工作日
    await controller.setMark('2026-10-15', DayMark.work(8));
    expect(controller.isWorkdayOn('2026-10-15'), isTrue);
    expect(controller.baseHoursOf('2026-10-15'), 8.0);
    expect(controller.hoursEarnings(30), 240); // 8h × 30
    expect(controller.fixedEarnings(200), 200); // 1 天 × 200
    expect(controller.workedDaysAll(), 1);

    // 10-16 标记休息日：不计收入
    await controller.setMark('2026-10-16', DayMark.rest());
    expect(controller.isWorkdayOn('2026-10-16'), isFalse);
    expect(controller.hoursAll(), 8.0);
    expect(controller.workedDaysAll(), 1);

    // 10-18 标记请假：不计收入不出勤
    await controller.setMark('2026-10-18', DayMark.leave());
    expect(controller.markOf('2026-10-18')?.isLeave, isTrue);
    expect(controller.isWorkdayOn('2026-10-18'), isFalse);
    expect(controller.baseHoursOf('2026-10-18'), 0.0);

    // 10-17 有打卡：打卡优先于标记（同天标记被忽略）
    await controller.addPunchAt(true, DateTime(2026, 10, 17, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 17, 13, 0));
    await controller.setMark('2026-10-17', DayMark.work(9));
    expect(controller.baseHoursOf('2026-10-17'), 4.0); // 按打卡 4 小时
    expect(controller.hoursAll(), 12.0);

    // 清除标记
    await controller.setMark('2026-10-15', null);
    expect(controller.markOf('2026-10-15'), isNull);
    expect(controller.hoursAll(), 4.0);

    // 持久化重载：标记仍存在（含请假）
    await controller.setMark('2026-10-15', DayMark.work(8));
    final second = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(second.markOf('2026-10-16')?.isRest, isTrue);
    expect(second.markOf('2026-10-18')?.isLeave, isTrue);
    expect(second.markOf('2026-10-15')?.isWork, isTrue);
    expect(second.markOf('2026-10-15')?.hours, 8);
    expect(second.hoursAll(), 12.0);

    // 清空数据同时清空标记
    await second.clearAll();
    expect(second.marks, isEmpty);
    expect(second.hoursAll(), 0.0);
  });

  test('加班：独立于打卡/标记，按加班时薪计酬，不重复计薪', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-15 打卡 4 小时 + 记加班 2 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 15, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 15, 13, 0));
    await controller.setOvertime('2026-10-15', 2);

    expect(controller.overtimeOf('2026-10-15'), 2);
    expect(controller.dayHoursOf('2026-10-15'), 6.0); // 4 基本 + 2 加班
    expect(controller.hoursAll(), 6.0);
    // 基本工时按普通时薪，加班按加班时薪，不重复
    expect(controller.hoursEarnings(20), 80); // 4h × 20
    expect(controller.overtimeEarnings(30), 60); // 2h × 30
    expect(
      controller.overtimeEarnings(
        30,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30),
      ),
      0,
    );

    // 休息日记加班：只有加班费
    await controller.setOvertime('2026-10-18', 1.5);
    expect(controller.overtimeHoursBetween(), 3.5);
    expect(controller.isWorkdayOn('2026-10-18'), isFalse); // 不算出勤
    // 只有打卡那天：4h 不足半个标准工时（4.5h）→ 半天 × ¥200 = ¥100
    expect(controller.fixedEarnings(200), 100);

    // 范围过滤
    expect(
      controller.overtimeHoursBetween(
        start: DateTime(2026, 10, 18),
        end: DateTime(2026, 10, 18),
      ),
      1.5,
    );

    // 清除加班
    await controller.setOvertime('2026-10-18', null);
    expect(controller.overtimeOf('2026-10-18'), 0);
    await controller.setOvertime('2026-10-15', 0); // <=0 视为清除
    expect(controller.overtimeOf('2026-10-15'), 0);
    expect(controller.hoursAll(), 4.0);

    // 持久化重载
    await controller.setOvertime('2026-10-16', 3);
    final second = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(second.overtimeOf('2026-10-16'), 3);

    // 清空数据同时清空加班
    await second.clearAll();
    expect(second.hoursAll(), 0.0);
    expect(second.overtimeHoursBetween(), 0);
  });

  test('月薪模式：出勤天数 × 月薪 ÷ 21.75', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 出勤 3 天（2 天打卡 + 1 天补记）
    await controller.addPunchAt(true, DateTime(2026, 10, 12, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 12, 18, 0));
    await controller.addPunchAt(true, DateTime(2026, 10, 13, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 13, 18, 0));
    await controller.setMark('2026-10-14', DayMark.work(0)); // 月薪模式补记无工时

    expect(controller.workedDaysAll(), 3);
    expect(controller.monthlyEarnings(5000), closeTo(5000 * 3 / 21.75, 1e-9));
    // 范围过滤
    expect(
      controller.monthlyEarnings(
        5000,
        start: DateTime(2026, 10, 13),
        end: DateTime(2026, 10, 14),
      ),
      closeTo(5000 * 2 / 21.75, 1e-9),
    );
    // 请假/休息不计薪
    await controller.setMark('2026-10-15', DayMark.leave());
    await controller.setMark('2026-10-16', DayMark.rest());
    expect(controller.workedDaysAll(), 3);
  });

  test('月薪折算方式：按当月实际天数逐日折算', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10 月出勤 2 天（10 月有 31 天），11 月出勤 1 天（11 月有 30 天）
    await controller.setMark('2026-10-12', DayMark.work(0));
    await controller.setMark('2026-10-13', DayMark.work(0));
    await controller.setMark('2026-11-02', DayMark.work(0));

    final byActual = controller.monthlyEarnings(5000, byActualDays: true);
    expect(byActual, closeTo(5000 / 31 * 2 + 5000 / 30, 1e-9));
    // 默认仍按 21.75
    expect(controller.monthlyEarnings(5000), closeTo(5000 * 3 / 21.75, 1e-9));
    // 范围过滤：只算 10 月
    expect(
      controller.monthlyEarnings(
        5000,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
        byActualDays: true,
      ),
      closeTo(5000 / 31 * 2, 1e-9),
    );
  });

  test('提成：按月设置、覆盖、清除与持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.setCommission(DateTime(2026, 10), 1500);
    await controller.setCommission(DateTime(2026, 9), 800);
    expect(controller.commissionOf(DateTime(2026, 10)), 1500);
    expect(controller.commissionOf(DateTime(2026, 8)), 0);
    expect(controller.commissionTotal, 2300);

    // 覆盖、清除（null 与 <=0 均视为清除）
    await controller.setCommission(DateTime(2026, 10), 2000);
    expect(controller.commissionTotal, 2800);
    await controller.setCommission(DateTime(2026, 9), null);
    await controller.setCommission(DateTime(2026, 8), 0);
    expect(controller.commissionTotal, 2000);
    expect(controller.commissions.length, 1);

    // 持久化重载
    final second = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(second.commissionOf(DateTime(2026, 10)), 2000);
    expect(second.commissionTotal, 2000);

    // 清空数据同时清空提成
    await second.clearAll();
    expect(second.commissionTotal, 0);
  });

  test('跨天夜班：时段按午夜切分分摊到两天', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-20 夜班：22:00 上班 → 10-21 06:00 下班，共 8 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 6, 0));

    // 按午夜切分：10-20 分得 22:00-24:00 共 2 小时
    expect(
      controller.sessionsOf('2026-10-20').single.duration,
      const Duration(hours: 2),
    );
    expect(controller.punchHoursOf('2026-10-20'), 2.0);
    // 10-21 分得 00:00-06:00 共 6 小时
    expect(
      controller.sessionsOf('2026-10-21').single.duration,
      const Duration(hours: 6),
    );
    expect(controller.punchHoursOf('2026-10-21'), 6.0);
    // 下班后不再处于上班状态
    expect(controller.isWorkingToday('2026-10-21'), isFalse);
    // 两天都有打卡记录，各算独立出勤
    expect(controller.hasPunchedOn('2026-10-20'), isTrue);
    expect(controller.hasPunchedOn('2026-10-21'), isTrue);
    expect(controller.workedDaysAll(), 2);
    expect(controller.isWorkdayOn('2026-10-21'), isTrue);

    // 日薪计薪：2h 不足半个标准工时算 0.5 天，6h 达标算 1 天
    const standard = 540;
    expect(controller.dayUnitsOf('2026-10-20', standard), 0.5);
    expect(controller.dayUnitsOf('2026-10-21', standard), 1.0);
    expect(
      controller.fixedEarnings(200, standardMinutes: standard),
      300,
    );

    // 当天先闭合前日夜班、再正常打卡自己的班：两天各自计工时
    await controller.addPunchAt(true, DateTime(2026, 10, 21, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 18, 0));
    expect(controller.punchHoursOf('2026-10-21'), 15.0);
    expect(controller.workedDaysAll(), 2);
  });

  test('跨天超24小时：时段分摊到多天，日薪按天计薪', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-20 09:00 上班 → 10-21 10:00 下班，共 25 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 10, 0));

    // 10-20 分得 15 小时，10-21 分得 10 小时
    expect(controller.punchHoursOf('2026-10-20'), 15.0);
    expect(controller.punchHoursOf('2026-10-21'), 10.0);
    expect(controller.hoursAll(), 25.0);

    // 日薪：两天均达标 → 2 天 × ¥200 = ¥400
    const standard = 540;
    expect(controller.dayUnitsOf('2026-10-20', standard), 1.0);
    expect(controller.dayUnitsOf('2026-10-21', standard), 1.0);
    expect(controller.fixedEarnings(200, standardMinutes: standard), 400);
  });

  test('时间线跨天上班卡补充：carryOverIn 返回配对的前日上班卡', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-20 22:00 上班 → 10-21 06:00 下班
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 6, 0));

    // 10-21 首笔为下班卡：补充显示配对的 10-20 22:00 上班卡
    final carry = controller.carryOverIn('2026-10-21');
    expect(carry, isNotNull);
    expect(carry!.time, DateTime(2026, 10, 20, 22, 0));
    // 上班当天与无打卡日不补充
    expect(controller.carryOverIn('2026-10-20'), isNull);
    expect(controller.carryOverIn('2026-10-22'), isNull);
  });

  test('跨天夜班进行中：前日未闭合上班卡延续为上班状态', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-20 22:00 上班，尚未打下班卡
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0));

    // 前日无已闭合时段，次日视为上班中（夜班延续）
    expect(controller.sessionsOf('2026-10-20'), isEmpty);
    expect(controller.isWorkingToday('2026-10-21'), isTrue);
    expect(controller.hasPunchedOn('2026-10-21'), isFalse);
    // 次日无打卡但夜班进行中：时间线补充显示前日上班卡
    final carry = controller.carryOverIn('2026-10-21');
    expect(carry, isNotNull);
    expect(carry!.time, DateTime(2026, 10, 20, 22, 0));
  });

  test('不分割模式：跨天时段整体归入下班日期', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // 10-20 夜班：22:00 上班 → 10-21 06:00 下班，共 8 小时
    controller.setJobSplits(const {'job1': false});
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 6, 0));

    // 整段 8 小时归下班日，上班日不再计工时
    expect(controller.sessionsOf('2026-10-20'), isEmpty);
    expect(controller.punchHoursOf('2026-10-20'), 0.0);
    expect(
      controller.sessionsOf('2026-10-21').single.duration,
      const Duration(hours: 8),
    );
    expect(controller.punchHoursOf('2026-10-21'), 8.0);

    // 打卡记录显示在下班日：上班日不再算有效打卡，出勤仅下班日 1 天
    expect(controller.hasPunchedOn('2026-10-20'), isFalse);
    expect(controller.hasPunchedOn('2026-10-21'), isTrue);
    expect(controller.workedDaysAll(), 1);
    expect(controller.isWorkdayOn('2026-10-20'), isFalse);
    expect(controller.isWorkdayOn('2026-10-21'), isTrue);

    // 日薪：整段 8 小时按 1 天计薪
    const standard = 540;
    expect(controller.dayUnitsOf('2026-10-20', standard), 0.0);
    expect(controller.dayUnitsOf('2026-10-21', standard), 1.0);
    expect(
      controller.fixedEarnings(200, standardMinutes: standard),
      200,
    );

    // 时间线补充：下班日仍显示前日的上班卡
    final carry = controller.carryOverIn('2026-10-21');
    expect(carry, isNotNull);
    expect(carry!.time, DateTime(2026, 10, 20, 22, 0));

    // 上班日当天另有独立班次时仍正常另计：10-20 白天半天班 08:00-10:30
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 8, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 20, 10, 30));
    expect(controller.punchHoursOf('2026-10-20'), 2.5);
    expect(controller.hasPunchedOn('2026-10-20'), isTrue);
    expect(controller.dayUnitsOf('2026-10-20', standard), 0.5);
    expect(controller.fixedEarnings(200, standardMinutes: standard), 300);

    // 切回分割模式：恢复午夜分摊口径（白班 2.5h + 夜班分摊 2h = 4.5h）
    controller.setJobSplits(const {'job1': true});
    expect(controller.punchHoursOf('2026-10-20'), 4.5);
    expect(controller.punchHoursOf('2026-10-21'), 6.0);
    expect(controller.hasPunchedOn('2026-10-20'), isTrue);
    expect(controller.workedDaysAll(), 2);
  });

  test('不分割模式：超24小时时段整段归下班日，只算一天', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    controller.setJobSplits(const {'job1': false});

    // 10-20 09:00 上班 → 10-21 10:00 下班，共 25 小时
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 9, 0));
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 10, 0));

    // 25 小时整段归下班日
    expect(controller.punchHoursOf('2026-10-20'), 0.0);
    expect(controller.punchHoursOf('2026-10-21'), 25.0);
    expect(controller.hoursAll(), 25.0);

    // 日薪按 1 天计：只算下班日 1 天，不再分摊多天
    const standard = 540;
    expect(controller.dayUnitsOf('2026-10-20', standard), 0.0);
    expect(controller.dayUnitsOf('2026-10-21', standard), 1.0);
    expect(controller.fixedEarnings(200, standardMinutes: standard), 200);
    expect(controller.workedDaysAll(), 1);
  });

  test('多工作跨天：各工作打卡互不串扰', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    controller.setJobSplits(const {'job1': false, 'job2': false});

    // job1 昨晚 22:00 上班（跨天进行中），job2 全程无打卡
    await controller.addPunchAt(
      true,
      DateTime(2026, 10, 20, 22, 0),
      jobId: 'job1',
    );

    // job2 视角：不显示 job1 的任何时间
    expect(controller.isWorkingToday('2026-10-21', jobId: 'job2'), isFalse);
    expect(controller.carryOverIn('2026-10-21', jobId: 'job2'), isNull);
    expect(controller.hasPunchedOn('2026-10-20', jobId: 'job2'), isFalse);
    expect(controller.punchesOf('2026-10-21', jobId: 'job2'), isEmpty);
    expect(
      controller.totalWorkTime('2026-10-21', jobId: 'job2'),
      Duration.zero,
    );

    // job1 视角：正常显示夜班延续
    expect(controller.isWorkingToday('2026-10-21', jobId: 'job1'), isTrue);
    final carry = controller.carryOverIn('2026-10-21', jobId: 'job1');
    expect(carry, isNotNull);
    expect(carry!.time, DateTime(2026, 10, 20, 22, 0));

    // 全部模式：只汇总 job1 的状态，不因 job2 产生误配
    expect(controller.isWorkingToday('2026-10-21'), isTrue);
    expect(
      controller.carryOverIn('2026-10-21')!.time,
      DateTime(2026, 10, 20, 22, 0),
    );
  });

  test('多工作交错打卡：全部模式按各工作独立配对', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-20：job2 08:00-10:00 闭合；job1 09:00 上班后未下班
    await controller.addPunchAt(
      true,
      DateTime(2026, 10, 20, 8, 0),
      jobId: 'job2',
    );
    await controller.addPunchAt(
      true,
      DateTime(2026, 10, 20, 9, 0),
      jobId: 'job1',
    );
    await controller.addPunchAt(
      false,
      DateTime(2026, 10, 20, 10, 0),
      jobId: 'job2',
    );

    // 全部模式：只有 job2 的 2 小时闭合时段（不再跨工作误配成 1 小时）
    expect(controller.punchHoursOf('2026-10-20'), 2.0);
    expect(controller.punchHoursOf('2026-10-20', jobId: 'job2'), 2.0);
    expect(controller.punchHoursOf('2026-10-20', jobId: 'job1'), 0.0);
    // 进行中归属：job1 仍在上班中，job2 已下班
    expect(controller.isWorkingToday('2026-10-20', jobId: 'job1'), isTrue);
    expect(controller.isWorkingToday('2026-10-20', jobId: 'job2'), isFalse);
  });

  test('不分割模式：进行中的跨天上班卡不在上班日记为打卡', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    controller.setJobSplits(const {'job1': false});

    // 10-20 22:00 上班，尚未打下班卡（进行中的跨天时段）
    await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0));

    // 上班日不再标为上班（整段将归入下班日期）
    expect(controller.hasPunchedOn('2026-10-20'), isFalse);
    expect(controller.isWorkdayOn('2026-10-20'), isFalse);
    // 时间线补充与进行中状态不受影响
    expect(controller.isWorkingToday('2026-10-21'), isTrue);
    expect(
      controller.carryOverIn('2026-10-21')!.time,
      DateTime(2026, 10, 20, 22, 0),
    );

    // 打下班卡后：整段归下班日，上班日依旧不算
    await controller.addPunchAt(false, DateTime(2026, 10, 21, 6, 0));
    expect(controller.hasPunchedOn('2026-10-20'), isFalse);
    expect(controller.hasPunchedOn('2026-10-21'), isTrue);
  });

  test('跨天分割按工作独立：一份分割一份不分割', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    controller.setJobSplits(const {'job1': true, 'job2': false});

    // 两份工作同样的夜班：10-20 22:00 上班 → 10-21 06:00 下班
    for (final j in ['job1', 'job2']) {
      await controller.addPunchAt(true, DateTime(2026, 10, 20, 22, 0), jobId: j);
      await controller.addPunchAt(false, DateTime(2026, 10, 21, 6, 0), jobId: j);
    }

    // job1（分割）：午夜分摊 2h + 6h，两天都算打卡
    expect(controller.punchHoursOf('2026-10-20', jobId: 'job1'), 2.0);
    expect(controller.punchHoursOf('2026-10-21', jobId: 'job1'), 6.0);
    expect(controller.hasPunchedOn('2026-10-20', jobId: 'job1'), isTrue);
    expect(controller.hasPunchedOn('2026-10-21', jobId: 'job1'), isTrue);

    // job2（不分割）：整段 8h 归下班日，上班日不算
    expect(controller.punchHoursOf('2026-10-20', jobId: 'job2'), 0.0);
    expect(controller.punchHoursOf('2026-10-21', jobId: 'job2'), 8.0);
    expect(controller.hasPunchedOn('2026-10-20', jobId: 'job2'), isFalse);
    expect(controller.hasPunchedOn('2026-10-21', jobId: 'job2'), isTrue);

    // 全部模式：两天各自合并（10-20 = job1 的 2h；10-21 = 6h + 8h）
    expect(controller.punchHoursOf('2026-10-20'), 2.0);
    expect(controller.punchHoursOf('2026-10-21'), 14.0);
    expect(controller.hoursAll(), 16.0);
  });

  test('时间线补充：隔多日的忘打卡不再补充显示', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 10-15 22:00 上班后忘打下班卡（已隔多日）
    await controller.addPunchAt(true, DateTime(2026, 10, 15, 22, 0));

    // 48 小时窗口外：不再当作进行中的夜班补充显示
    expect(controller.carryOverIn('2026-10-17'), isNull);
    expect(controller.isWorkingToday('2026-10-17'), isFalse);
    // 窗口内（次日）：仍正常补充
    expect(controller.carryOverIn('2026-10-16'), isNotNull);
  });

  test('简洁模式：一键生成闭合时段，日薪计整天，整体撤销', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final key = dayKeyOf(DateTime(2026, 10, 24));

    // 一键打卡：09:00 → 18:00 生成闭合时段
    await controller.punchSession(
      DateTime(2026, 10, 24, 9, 0),
      DateTime(2026, 10, 24, 18, 0),
    );
    expect(controller.punchesOf(key).length, 2);
    expect(controller.isWorkingToday(key), isFalse);
    expect(controller.totalWorkTime(key), const Duration(hours: 9));
    // 日薪按整天计薪
    expect(
      controller.fixedEarnings(
        200,
        start: DateTime(2026, 10, 24),
        end: DateTime(2026, 10, 24),
      ),
      200,
    );

    // 撤销：上下班两卡一并移除，收入归零
    await controller.undoLastSession();
    expect(controller.punchesOf(key), isEmpty);
    expect(
      controller.fixedEarnings(
        200,
        start: DateTime(2026, 10, 24),
        end: DateTime(2026, 10, 24),
      ),
      0,
    );

    // 时薪输入工时：16:00 → 18:00 生成 2 小时时段
    await controller.punchSession(
      DateTime(2026, 10, 24, 16, 0),
      DateTime(2026, 10, 24, 18, 0),
    );
    expect(
      controller.hoursEarnings(
        20,
        start: DateTime(2026, 10, 24),
        end: DateTime(2026, 10, 24),
      ),
      40,
    );
    await controller.undoLastSession();
    expect(controller.punchesOf(key), isEmpty);
  });

  test('简洁模式撤销：进行中上班卡与跨天闭合时段', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = RecordsController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 进行中的上班卡：撤销仅移除该卡
    await controller.addPunchAt(true, DateTime(2026, 10, 23, 9, 0));
    await controller.undoLastSession();
    expect(controller.punchesOf('2026-10-23'), isEmpty);

    // 跨天闭合时段：22:00 → 次日 06:00，撤销两卡一并移除
    await controller.punchSession(
      DateTime(2026, 10, 23, 22, 0),
      DateTime(2026, 10, 24, 6, 0),
    );
    expect(controller.punchesOf('2026-10-23').length, 1);
    expect(controller.punchesOf('2026-10-24').length, 1);
    await controller.undoLastSession();
    expect(controller.punchesOf('2026-10-23'), isEmpty);
    expect(controller.punchesOf('2026-10-24'), isEmpty);
  });
}
