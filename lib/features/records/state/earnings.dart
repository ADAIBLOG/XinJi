import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

/// 时薪基本工资。自动加班且有加班费时按标准工时封顶计薪
///（超出部分改按加班时薪计，避免加班部分重复按时薪）；
/// 其余情况（未开启自动加班或无加班费）按全部基本工时计薪。
/// [autoOtOn]/[paidOn] 为该计算口径下生效的开关值（分段时按日传入）。
double _hourlyBase(
  Job job,
  RecordsController records,
  double autoOt, {
  required bool autoOtOn,
  required bool paidOn,
  DateTime? start,
  DateTime? end,
}) {
  final full = records.hoursEarnings(
    job.hourlyRate,
    start: start,
    end: end,
    jobId: job.id,
  );
  if (!autoOtOn || !paidOn) return full;
  final fullHours = start == null
      ? records.baseHoursAll(jobId: job.id)
      : records.baseHoursBetween(start, end ?? start, jobId: job.id);
  return (fullHours - autoOt) * job.hourlyRate;
}

/// 当月应出勤天数：当月总天数 − 排班休息天数 − 手动标记休息天数。
/// 月薪「按实际天数折算」的分母——排班休息与手动休息（如法定节假日
/// 多休）都不扣钱，其余工作日上满即全额月薪；请假/缺勤仍按比例扣。
/// 手动休息标记在排班休息日上时不重复扣除。
int expectedWorkDaysInMonth(
  Job job,
  RecordsController records,
  DateTime month,
) {
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  var work = 0;
  for (var d = 1; d <= daysInMonth; d++) {
    final day = DateTime(month.year, month.month, d);
    if (job.isScheduledRest(day)) continue;
    final mark = records.markOf(dayKeyOf(day), jobId: job.id);
    if (mark != null && mark.isRest) continue;
    work++;
  }
  return work;
}

/// 单份工作收入（含加班），按给定开关口径计算一个日期范围。
double _earningsOfJobCalc(
  Job job,
  RecordsController records, {
  DateTime? start,
  DateTime? end,
  required bool autoOtOn,
  required bool paidOn,
}) {
  final standard = job.standardWorkMinutes;
  // 自动加班工时：固定上下班时间开启后，每日基本工时超出标准工时的部分
  //（不含手动记的加班，两者相加互不重复）。
  final autoOt = autoOtOn
      ? records.autoOvertimeHours(standard, start: start, end: end, jobId: job.id)
      : 0.0;
  final base = switch (job.calcMode) {
    CalcMode.hourly => _hourlyBase(
      job,
      records,
      autoOt,
      autoOtOn: autoOtOn,
      paidOn: paidOn,
      start: start,
      end: end,
    ),
    CalcMode.fixedDaily => records.fixedEarnings(
      job.dailyWage,
      start: start,
      end: end,
      standardMinutes: standard,
      jobId: job.id,
    ),
    CalcMode.monthly => records.monthlyEarnings(
      job.monthlySalary,
      start: start,
      end: end,
      byActualDays: job.monthlyByActualDays,
      expectedWorkDaysOf: (month) =>
          expectedWorkDaysInMonth(job, records, month),
      standardMinutes: standard,
      jobId: job.id,
    ),
  };
  // 加班金额：无加班费时只统计工时，不增加金额（手动、自动加班均不计钱）。
  final overtimePay = !paidOn
      ? 0.0
      : records.overtimeEarnings(
            job.overtimeRate,
            start: start,
            end: end,
            jobId: job.id,
          ) +
          autoOt * job.overtimeRate;
  return base + overtimePay;
}

/// 单份工作收入（含加班）。
/// - 时薪：打卡/补记基本工时 × 时薪（自动加班时标准工时封顶，超出按加班时薪）
/// - 日薪：计薪天数 × 日薪（打完下班卡才计；时长 ≥ 半个标准工时为整天，否则半天）
/// - 月薪：计薪天数 × 月薪 ÷ 21.75（或按出勤日所在月实际天数折算）
/// - 加班：手动加班 + 自动加班（超出标准工时的部分）× 加班时薪；
///   无加班费时只统计加班工时，不增加金额
///
/// 分段口径：任一开关存在分段历史时按日取生效开关逐日计算，
/// 历史日期保持当时的开关状态；无分段时当前开关对全部日期生效。
double _earningsOfJob(
  Job job,
  RecordsController records, {
  DateTime? start,
  DateTime? end,
}) {
  if (!job.hasSwitchHistory) {
    return _earningsOfJobCalc(
      job,
      records,
      start: start,
      end: end,
      autoOtOn: job.autoOvertime,
      paidOn: job.overtimePaid,
    );
  }
  // 分段口径：从最早记录日（或 start）逐日按当日生效开关累加
  DateTime first;
  if (start != null) {
    first = DateTime(start.year, start.month, start.day);
  } else {
    final earliest = records.earliestDataDate(jobId: job.id);
    if (earliest == null) return 0;
    first = earliest;
  }
  final last = end ?? DateTime.now();
  var sum = 0.0;
  for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
    sum += _earningsOfJobCalc(
      job,
      records,
      start: d,
      end: d,
      autoOtOn: job.effectiveAutoOvertime(d),
      paidOn: job.effectiveOvertimePaid(d),
    );
  }
  return sum;
}

/// 收入（含加班）。[jobId] 为空表示全部工作逐份计算后求和。
/// [start]/[end] 为空表示统计全部（按天，含边界）。
double earningsOf(
  SettingsController settings,
  RecordsController records, {
  DateTime? start,
  DateTime? end,
  String? jobId,
}) {
  if (jobId != null) {
    final job = settings.jobById(jobId);
    return job == null
        ? 0
        : _earningsOfJob(job, records, start: start, end: end);
  }
  var sum = 0.0;
  for (final job in settings.jobs) {
    sum += _earningsOfJob(job, records, start: start, end: end);
  }
  return sum;
}

/// 出勤/计薪天数：时薪模式为出勤天数（信息展示），日薪/月薪为计薪天数。
/// [jobId] 为空表示全部工作逐份计算后求和。
double daysOf(
  SettingsController settings,
  RecordsController records, {
  DateTime? start,
  DateTime? end,
  String? jobId,
}) {
  double ofJob(Job job) => switch (job.calcMode) {
    CalcMode.hourly =>
      (start == null
              ? records.workedDaysAll(jobId: job.id)
              : records.workedDaysBetween(start, end ?? start, jobId: job.id))
          .toDouble(),
    _ => records.paidDays(
      start: start,
      end: end,
      standardMinutes: job.standardWorkMinutes,
      jobId: job.id,
    ),
  };
  if (jobId != null) {
    final job = settings.jobById(jobId);
    return job == null ? 0 : ofJob(job);
  }
  var sum = 0.0;
  for (final job in settings.jobs) {
    sum += ofJob(job);
  }
  return sum;
}

/// 某月税前收入：工资 + 加班 + 当月提成。
double grossEarningsOfMonth(
  SettingsController settings,
  RecordsController records,
  DateTime month, {
  String? jobId,
}) {
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  return earningsOf(
        settings,
        records,
        start: month,
        end: monthEnd,
        jobId: jobId,
      ) +
      records.commissionOf(month, jobId: jobId);
}

/// 单份工作的个税（近似）：月收入超过起征点的部分 × 税率。
/// 未超起征点时为 0（开关是否生效由调用方按分段口径判定）。
double taxOfJob(Job job, double grossEarnings) {
  final taxable = grossEarnings - job.taxThreshold;
  return taxable > 0 ? taxable * job.taxRate : 0;
}

/// 该月个税是否生效（按月整体口径）：取该月最后一天的生效值。
/// 个税是月度口径——开启当月一起计税，关闭当月一起不计，不按日
/// 拆分。当月的末段值即当前开关值（切换后当月立即整月按新状态），
/// 历史月份按该月当时的最后口径。
bool taxEffectiveInMonth(Job job, DateTime month) {
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  return job.effectiveTaxEnabled(monthEnd);
}

/// 某月个税合计：[jobId] 为空时各工作按自己的起征点/税率分别计税后求和
///（不合并计算，各自起征点独立扣除）。
double taxOfMonth(
  SettingsController settings,
  RecordsController records,
  DateTime month, {
  String? jobId,
}) {
  double ofJob(Job job) => !taxEffectiveInMonth(job, month)
      ? 0.0
      : taxOfJob(job, grossEarningsOfMonth(settings, records, month, jobId: job.id));
  if (jobId != null) {
    final job = settings.jobById(jobId);
    return job == null ? 0 : ofJob(job);
  }
  var sum = 0.0;
  for (final job in settings.jobs) {
    sum += ofJob(job);
  }
  return sum;
}

/// 某月税后收入：税前 − 当月个税（各工作独立计税）。
double netEarningsOfMonth(
  SettingsController settings,
  RecordsController records,
  DateTime month, {
  String? jobId,
}) {
  if (jobId != null) {
    final job = settings.jobById(jobId);
    final gross = grossEarningsOfMonth(settings, records, month, jobId: jobId);
    final tax = job != null && taxEffectiveInMonth(job, month)
        ? taxOfJob(job, gross)
        : 0.0;
    return gross - tax;
  }
  var net = 0.0;
  for (final job in settings.jobs) {
    final gross = grossEarningsOfMonth(settings, records, month, jobId: job.id);
    final tax = taxEffectiveInMonth(job, month) ? taxOfJob(job, gross) : 0.0;
    net += gross - tax;
  }
  return net;
}

/// 某日税后收入：今日税前 − 按今日收入占本月税前收入比例分摊的个税
///（个税为月度口径，按比例折算到日；本月无税或本月无收入时不扣）。
double netEarningsOfDay(
  SettingsController settings,
  RecordsController records,
  DateTime day, {
  String? jobId,
}) {
  final gross = earningsOf(settings, records, start: day, end: day, jobId: jobId);
  final month = DateTime(day.year, day.month);
  final monthGross = grossEarningsOfMonth(
    settings,
    records,
    month,
    jobId: jobId,
  );
  final tax = taxOfMonth(settings, records, month, jobId: jobId);
  if (monthGross <= 0 || tax <= 0) return gross;
  return gross - tax * (gross / monthGross);
}

/// 逐月计算范围内的税后收入与扣税合计（月度粒度统计用）。
/// [start]/[end] 为日期范围（含边界），按其覆盖的整月逐月计算。
/// 返回 (税后合计, 扣税合计)。
({double net, double tax}) netEarningsOfMonths(
  SettingsController settings,
  RecordsController records,
  DateTime start,
  DateTime end, {
  String? jobId,
}) {
  var net = 0.0;
  var tax = 0.0;
  var month = DateTime(start.year, start.month);
  final last = DateTime(end.year, end.month);
  while (!month.isAfter(last)) {
    net += netEarningsOfMonth(settings, records, month, jobId: jobId);
    tax += taxOfMonth(settings, records, month, jobId: jobId);
    month = DateTime(month.year, month.month + 1);
  }
  return (net: net, tax: tax);
}
