import 'package:flutter/material.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/core/utils/day_key.dart';

/// 薪资方式：时薪（按打卡工时）、日薪（出勤一天算一天）或月薪（按月折算，出勤比例计薪）。
enum CalcMode { hourly, fixedDaily, monthly }

/// 休息日排班方式。
/// - flexible 无固定休息
/// - fixed 每周固定休息（自选星期）
/// - alternate 大小周（每周日休，周六隔周休）
enum RestSchedule { flexible, fixed, alternate }

/// 今日页收入卡标签（显示与顺序）。
/// - hours 工时 / overtime 加班 / rate 薪资（时薪·日薪·月薪）/ tax 个税
const kHeroTagIds = ['hours', 'overtime', 'rate', 'tax'];
const kDefaultHeroTags = ['hours', 'overtime', 'rate', 'tax'];

/// 开关分段历史条目：from 为生效日（dateKey，'' 表示自最早记录起），
/// value 为该段起开关的状态；按 from 升序，末段值与开关当前值一致。
typedef SwitchSegment = ({String from, bool value});

/// 支持分段生效（仅今后 / 同步历史）的工作开关。
enum JobSwitch { tax, overtimePaid, autoOvertime }

/// 一份工作：独立的薪资方式、薪资、上下班时间与休息日排班。
class Job {
  Job({
    required this.id,
    required this.name,
    this.calcMode = CalcMode.hourly,
    this.hourlyRate = 20,
    this.dailyWage = 200,
    this.monthlySalary = 5000,
    this.monthlyByActualDays = false,
    this.overtimeRate = 30,
    this.autoOvertime = false,
    this.overtimePaid = true,
    this.workStart = 540,
    this.workEnd = 1080,
    this.restMode = RestSchedule.flexible,
    Set<int>? fixedRestWeekdays,
    DateTime? altAnchorMonday,
    this.altAnchorIsBig = false,
    this.colorIndex = -1,
    this.splitOvernight = true,
    this.punchMode = 2,
    this.punchReminders = false,
    List<int>? reminderMinutes,
    this.taxEnabled = false,
    this.taxThreshold = 5000,
    this.taxRate = 0.03,
    List<String>? heroTags,
    List<SwitchSegment>? taxHistory,
    List<SwitchSegment>? otPaidHistory,
    List<SwitchSegment>? autoOtHistory,
  }) : fixedRestWeekdays =
           fixedRestWeekdays ?? {DateTime.saturday, DateTime.sunday},
       altAnchorMonday = altAnchorMonday ?? weekStartOf(DateTime.now()),
       heroTags = heroTags ?? [...kDefaultHeroTags],
       reminderMinutes = reminderMinutes ?? [],
       taxHistory = taxHistory ?? [],
       otPaidHistory = otPaidHistory ?? [],
       autoOtHistory = autoOtHistory ?? [];

  final String id;
  String name;

  /// 今日页收入卡标签：显示哪些及排列顺序（每工作独立）。
  List<String> heroTags;

  /// 薪资方式。
  CalcMode calcMode;

  /// 时薪。
  double hourlyRate;

  /// 日薪。
  double dailyWage;

  /// 月薪。
  double monthlySalary;

  /// 月薪折算方式：false 按平均计薪天数 21.75，true 按出勤日所在月实际天数。
  bool monthlyByActualDays;

  /// 加班时薪。
  double overtimeRate;

  /// 固定上下班时间自动记加班：开启后当日工时超出标准工时的部分自动计为加班。
  bool autoOvertime;

  /// 是否有加班费：关闭后只统计加班工时，不增加加班金额。
  bool overtimePaid;

  /// 上班时刻（当天分钟数）。
  int workStart;

  /// 下班时刻（当天分钟数）。
  int workEnd;

  /// 休息日排班方式。
  RestSchedule restMode;

  /// 每周固定休息的星期（周一=1 … 周日=7）。
  Set<int> fixedRestWeekdays;

  /// 大小周参照周（锚点周一）。
  DateTime altAnchorMonday;

  /// 锚点周是否为大周（单休）。
  bool altAnchorIsBig;

  /// 标识色索引（AppPalette.jobColors；-1 表示未指定，加载时按位置补齐）。
  int colorIndex;

  /// 跨天打卡是否按午夜分割分摊（false 时整段工时归下班日期）。
  bool splitOvernight;

  /// 打卡模式：1=简洁（一键打卡） 2=精准（上下班两次打卡）。
  int punchMode;

  /// 打卡提醒开关（应用内通知，按 [reminderMinutes] 时间点提醒）。
  bool punchReminders;

  /// 自定义提醒时间点（当天分钟数，如 540=09:00）；可设多个，与上下班时间无关。
  List<int> reminderMinutes;

  /// 是否开启个税扣除（近似：月起征点 + 单一税率）。
  bool taxEnabled;

  /// 个税月起征点。
  double taxThreshold;

  /// 个税税率（0~1，如 3% 存 0.03）。
  double taxRate;

  /// 个税开关分段历史（空 = 无分段，全历史按当前值）。
  List<SwitchSegment> taxHistory;

  /// 加班费开关分段历史（空 = 无分段）。
  List<SwitchSegment> otPaidHistory;

  /// 自动加班开关分段历史（空 = 无分段）。
  List<SwitchSegment> autoOtHistory;

  /// 任一开关存在分段历史（计算需按日取生效值）。
  bool get hasSwitchHistory =>
      taxHistory.length > 1 ||
      otPaidHistory.length > 1 ||
      autoOtHistory.length > 1;

  /// 规整分段列表：空列表视为单一全历史段（当前值）。
  static List<SwitchSegment> _segments(
    List<SwitchSegment> history,
    bool current,
  ) => history.isEmpty ? [(from: '', value: current)] : history;

  /// 分段开关在某天生效的值。
  static bool _effectiveAt(
    List<SwitchSegment> history,
    bool current,
    DateTime day,
  ) {
    final segments = _segments(history, current);
    final key = dayKeyOf(day);
    var value = segments.first.value;
    for (final seg in segments) {
      if (seg.from.isEmpty || seg.from.compareTo(key) <= 0) {
        value = seg.value;
      } else {
        break;
      }
    }
    return value;
  }

  /// 个税开关在 [day] 生效的值。
  bool effectiveTaxEnabled(DateTime day) =>
      _effectiveAt(taxHistory, taxEnabled, day);

  /// 加班费开关在 [day] 生效的值。
  bool effectiveOvertimePaid(DateTime day) =>
      _effectiveAt(otPaidHistory, overtimePaid, day);

  /// 自动加班开关在 [day] 生效的值。
  bool effectiveAutoOvertime(DateTime day) =>
      _effectiveAt(autoOtHistory, autoOvertime, day);

  /// 切换分段开关。
  /// - [fromNowOnly] true：仅今后生效——历史日期保持原口径，从今天起新值；
  ///   false：同步当月——本月整月按新值，之前的月份保持各自当时的口径
  ///   （保留当月 1 日前的原分段，历史月份永不被改写）。
  Job copyWithSwitch(JobSwitch s, bool value, {required bool fromNowOnly}) {
    List<SwitchSegment> apply(List<SwitchSegment> history, bool current) {
      final segments = _segments(history, current);
      if (!fromNowOnly) {
        // 同步当月：保留当月 1 日之前的段（含 '' 基线段），追加当月新值段
        final monthKey = dayKeyOf(
          DateTime(DateTime.now().year, DateTime.now().month),
        );
        final before = segments
            .where((seg) => seg.from.compareTo(monthKey) < 0)
            .toList();
        return [...before, (from: monthKey, value: value)];
      }
      final today = dayKeyOf(DateTime.now());
      final kept = segments
          .where((seg) => seg.from != today)
          .toList();
      return [...kept, (from: today, value: value)];
    }

    return copyWith(
      taxEnabled: s == JobSwitch.tax ? value : null,
      taxHistory: s == JobSwitch.tax ? apply(taxHistory, taxEnabled) : null,
      overtimePaid: s == JobSwitch.overtimePaid ? value : null,
      otPaidHistory: s == JobSwitch.overtimePaid
          ? apply(otPaidHistory, overtimePaid)
          : null,
      autoOvertime: s == JobSwitch.autoOvertime ? value : null,
      autoOtHistory: s == JobSwitch.autoOvertime
          ? apply(autoOtHistory, autoOvertime)
          : null,
    );
  }

  /// 工作标识色。
  Color get color =>
      AppPalette.jobColors[colorIndex < 0
          ? 0
          : colorIndex % AppPalette.jobColors.length];

  /// 标准工时（分钟）：下班-上班；无效配置时按 9 小时。
  int get standardWorkMinutes {
    final minutes = workEnd - workStart;
    return minutes > 0 ? minutes : 540;
  }

  /// 配置的班次长度（分钟），跨天夜班按次日下班计算
  /// （如 22:00–10:00 → 12 小时）；上下班时间相同或无效时按 9 小时。
  /// 用于忘打卡补记工作日时回填显示工时，不改变计薪口径。
  int get shiftMinutes {
    if (workEnd == workStart) return 540;
    final minutes = (workEnd - workStart) % 1440;
    return minutes > 0 ? minutes : 540;
  }

  /// 某天是否为排班休息日。
  /// - 无固定：false
  /// - 固定休息：选中星期
  /// - 大小周：每周日休；周六在小周（双休）休，大周（单休）上班
  bool isScheduledRest(DateTime day) {
    switch (restMode) {
      case RestSchedule.flexible:
        return false;
      case RestSchedule.fixed:
        return fixedRestWeekdays.contains(day.weekday);
      case RestSchedule.alternate:
        if (day.weekday == DateTime.sunday) return true;
        if (day.weekday != DateTime.saturday) return false;
        final dayMonday = DateTime(
          day.year,
          day.month,
          day.day - (day.weekday - 1),
        );
        final diff = dayMonday.difference(altAnchorMonday).inDays ~/ 7;
        final sameParity = ((diff % 2) + 2) % 2 == 0;
        final isBigWeek = sameParity ? altAnchorIsBig : !altAnchorIsBig;
        return !isBigWeek; // 小周（双休）周六休息
    }
  }

  /// 当前周是否为大周（单休）。大小周模式下用于「本周是」显示。
  bool get currentWeekIsBig {
    final nowMonday = weekStartOf(DateTime.now());
    final diff = nowMonday.difference(altAnchorMonday).inDays ~/ 7;
    final sameParity = ((diff % 2) + 2) % 2 == 0;
    return sameParity ? altAnchorIsBig : !altAnchorIsBig;
  }

  Job copyWith({
    String? name,
    CalcMode? calcMode,
    double? hourlyRate,
    double? dailyWage,
    double? monthlySalary,
    bool? monthlyByActualDays,
    double? overtimeRate,
    bool? autoOvertime,
    bool? overtimePaid,
    int? workStart,
    int? workEnd,
    RestSchedule? restMode,
    Set<int>? fixedRestWeekdays,
    DateTime? altAnchorMonday,
    bool? altAnchorIsBig,
    int? colorIndex,
    bool? splitOvernight,
    int? punchMode,
    bool? punchReminders,
    List<int>? reminderMinutes,
    bool? taxEnabled,
    double? taxThreshold,
    double? taxRate,
    List<String>? heroTags,
    List<SwitchSegment>? taxHistory,
    List<SwitchSegment>? otPaidHistory,
    List<SwitchSegment>? autoOtHistory,
  }) => Job(
    id: id,
    name: name ?? this.name,
    calcMode: calcMode ?? this.calcMode,
    hourlyRate: hourlyRate ?? this.hourlyRate,
    dailyWage: dailyWage ?? this.dailyWage,
    monthlySalary: monthlySalary ?? this.monthlySalary,
    monthlyByActualDays: monthlyByActualDays ?? this.monthlyByActualDays,
    overtimeRate: overtimeRate ?? this.overtimeRate,
    autoOvertime: autoOvertime ?? this.autoOvertime,
    overtimePaid: overtimePaid ?? this.overtimePaid,
    workStart: workStart ?? this.workStart,
    workEnd: workEnd ?? this.workEnd,
    restMode: restMode ?? this.restMode,
    fixedRestWeekdays: fixedRestWeekdays ?? this.fixedRestWeekdays,
    altAnchorMonday: altAnchorMonday ?? this.altAnchorMonday,
    altAnchorIsBig: altAnchorIsBig ?? this.altAnchorIsBig,
    colorIndex: colorIndex ?? this.colorIndex,
    splitOvernight: splitOvernight ?? this.splitOvernight,
    punchMode: punchMode ?? this.punchMode,
    punchReminders: punchReminders ?? this.punchReminders,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    taxEnabled: taxEnabled ?? this.taxEnabled,
    taxThreshold: taxThreshold ?? this.taxThreshold,
    taxRate: taxRate ?? this.taxRate,
    heroTags: heroTags ?? this.heroTags,
    taxHistory: taxHistory ?? this.taxHistory,
    otPaidHistory: otPaidHistory ?? this.otPaidHistory,
    autoOtHistory: autoOtHistory ?? this.autoOtHistory,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'calcMode': calcMode.index,
    'hourlyRate': hourlyRate,
    'dailyWage': dailyWage,
    'monthlySalary': monthlySalary,
    'monthlyByActualDays': monthlyByActualDays,
    'overtimeRate': overtimeRate,
    'autoOvertime': autoOvertime,
    'overtimePaid': overtimePaid,
    'workStart': workStart,
    'workEnd': workEnd,
    'restMode': restMode.index,
    'fixedRest': fixedRestWeekdays.toList()..sort(),
    'altAnchor': dayKeyOf(altAnchorMonday),
    'altIsBig': altAnchorIsBig,
    'colorIndex': colorIndex,
    'splitOvernight': splitOvernight,
    'punchMode': punchMode,
    'punchReminders': punchReminders,
    'reminderMinutes': reminderMinutes,
    'taxEnabled': taxEnabled,
    'taxThreshold': taxThreshold,
    'taxRate': taxRate,
    'heroTags': heroTags,
    // 分段历史仅在有实际分段时保存（旧数据/无分段不写入，保持兼容）
    if (taxHistory.length > 1)
      'taxHistory': [for (final s in taxHistory) {'from': s.from, 'v': s.value}],
    if (otPaidHistory.length > 1)
      'otPaidHistory': [
        for (final s in otPaidHistory) {'from': s.from, 'v': s.value},
      ],
    if (autoOtHistory.length > 1)
      'autoOtHistory': [
        for (final s in autoOtHistory) {'from': s.from, 'v': s.value},
      ],
  };

  static Job fromJson(Map<String, dynamic> json) {
    final modeIndex = json['calcMode'] as int? ?? 0;
    final restIndex = json['restMode'] as int? ?? 0;
    DateTime? anchor;
    final anchorRaw = json['altAnchor'] as String?;
    if (anchorRaw != null && anchorRaw.length == 10) {
      final y = int.tryParse(anchorRaw.substring(0, 4));
      final m = int.tryParse(anchorRaw.substring(5, 7));
      final d = int.tryParse(anchorRaw.substring(8, 10));
      if (y != null && m != null && d != null) anchor = DateTime(y, m, d);
    }
    Set<int>? fixedRest;
    final fixedRaw = json['fixedRest'] as List?;
    if (fixedRaw != null && fixedRaw.isNotEmpty) {
      fixedRest = fixedRaw
          .map((e) => e as int)
          .where((w) => w >= 1 && w <= 7)
          .toSet();
    }
    final rate = (json['taxRate'] as num?)?.toDouble();
    // 今日页标签：过滤未知值；列表可能只是排序子集（隐藏项不在内）
    List<String>? heroTags;
    final tagsRaw = json['heroTags'] as List?;
    if (tagsRaw != null) {
      heroTags = tagsRaw
          .map((e) => e as String)
          .where(kHeroTagIds.contains)
          .toList();
    }
    // 分段历史：解析 + 升序 + 去重同日；空/缺省 = 无分段
    List<SwitchSegment> parseSegments(String key, bool fallback) {
      final raw = json[key] as List?;
      if (raw == null) return [];
      final segs = <SwitchSegment>[];
      for (final e in raw) {
        if (e is! Map) continue;
        segs.add((
          from: e['from'] as String? ?? '',
          value: e['v'] as bool? ?? fallback,
        ));
      }
      segs.sort((a, b) => a.from.compareTo(b.from));
      // 相邻同日去重（保留最后一条）
      final deduped = <SwitchSegment>[];
      for (final s in segs) {
        if (deduped.isNotEmpty && deduped.last.from == s.from) {
          deduped[deduped.length - 1] = s;
        } else {
          deduped.add(s);
        }
      }
      return deduped;
    }

    final taxEnabledValue = json['taxEnabled'] as bool? ?? false;
    final otPaidValue = json['overtimePaid'] as bool? ?? true;
    final autoOtValue = json['autoOvertime'] as bool? ?? false;
    return Job(
      id: json['id'] as String,
      name: json['name'] as String? ?? '工作',
      calcMode: modeIndex >= 0 && modeIndex < CalcMode.values.length
          ? CalcMode.values[modeIndex]
          : CalcMode.hourly,
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble() ?? 20,
      dailyWage: (json['dailyWage'] as num?)?.toDouble() ?? 200,
      monthlySalary: (json['monthlySalary'] as num?)?.toDouble() ?? 5000,
      monthlyByActualDays: json['monthlyByActualDays'] as bool? ?? false,
      overtimeRate: (json['overtimeRate'] as num?)?.toDouble() ?? 30,
      autoOvertime: autoOtValue,
      overtimePaid: otPaidValue,
      workStart: json['workStart'] as int? ?? 540,
      workEnd: json['workEnd'] as int? ?? 1080,
      restMode: restIndex >= 0 && restIndex < RestSchedule.values.length
          ? RestSchedule.values[restIndex]
          : RestSchedule.flexible,
      fixedRestWeekdays: (fixedRest == null || fixedRest.isEmpty)
          ? null
          : fixedRest,
      altAnchorMonday: anchor,
      altAnchorIsBig: json['altIsBig'] as bool? ?? false,
      colorIndex: json['colorIndex'] as int? ?? -1,
      splitOvernight: json['splitOvernight'] as bool? ?? true,
      punchMode: (json['punchMode'] as int?) == 1 ? 1 : 2,
      punchReminders: json['punchReminders'] as bool? ?? false,
      // 旧数据迁移：无自定义时间但开关开启 → 沿用上下班时间作为提醒点
      reminderMinutes: () {
        final raw = json['reminderMinutes'] as List?;
        final values = raw != null
            ? raw.whereType<int>()
            : (json['punchReminders'] as bool? ?? false)
            ? [
                json['workStart'] as int? ?? 540,
                json['workEnd'] as int? ?? 1080,
              ]
            : const <int>[];
        // 排序去重并过滤非法值（旧数据/异常导入可能带重复或越界分钟）
        return values.where((m) => m >= 0 && m < 1440).toSet().toList()..sort();
      }(),
      taxEnabled: taxEnabledValue,
      taxThreshold: (json['taxThreshold'] as num?)?.toDouble() ?? 5000,
      taxRate: rate != null && rate > 0 && rate < 1 ? rate : 0.03,
      heroTags: heroTags == null || heroTags.isEmpty
          ? null
          : heroTags,
      taxHistory: parseSegments('taxHistory', taxEnabledValue),
      otPaidHistory: parseSegments('otPaidHistory', otPaidValue),
      autoOtHistory: parseSegments('autoOtHistory', autoOtValue),
    );
  }
}
