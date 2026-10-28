import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/records/data/day_mark.dart';
import 'package:xinji/features/records/data/punch_record.dart';

/// 工资记录仓库：按工作维度记录打卡、日期标记、加班与提成，
/// shared_preferences + JSON 持久化。
///
/// 记录结构（jobId 维度）：
/// - punch：{jobId, isIn, time}
/// - marks：dateKey → {jobId → DayMark}
/// - overtime：dateKey → {jobId → hours}
/// - commissions：yyyy-MM → {jobId → amount}
///
/// 各查询方法带可选 [jobId]：null 表示全部工作聚合。
class RecordsController extends ChangeNotifier {
  RecordsController() {
    _load();
  }

  static const _punchKey = 'xinji.punches';
  static const _markKey = 'xinji.dayMarks';
  static const _overtimeKey = 'xinji.overtime';
  static const _commissionKey = 'xinji.commissions';

  /// 迁移工作 id：旧数据（无工作归属）与默认写入归入该工作。
  static const _migratedJobId = 'job1';

  List<PunchRecord> _punches = [];

  /// 日期标记：dateKey → jobId → 标记。
  Map<String, Map<String, DayMark>> _marks = {};

  /// 加班工时（小时）：dateKey → jobId → 小时。
  Map<String, Map<String, double>> _overtime = {};

  /// 提成：月键 yyyy-MM → jobId → 金额。
  Map<String, Map<String, double>> _commissions = {};

  bool _loaded = false;

  List<PunchRecord> get punches => List.unmodifiable(_punches);

  /// 日期标记（dateKey → jobId → 标记），外层长度即有标记的天数。
  Map<String, Map<String, DayMark>> get marks => _marks;

  /// 加班记录（dateKey → jobId → 小时），外层长度即有加班的天数。
  Map<String, Map<String, double>> get overtime => _overtime;

  /// 提成（yyyy-MM → jobId → 金额）。
  Map<String, Map<String, double>> get commissions => _commissions;

  bool get loaded => _loaded;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final punchRaw = prefs.getString(_punchKey);
    _punches = [];
    var punchesMigrated = false;
    if (punchRaw != null && punchRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(punchRaw) as List)
            .map((e) => PunchRecord.fromJson(e as Map<String, dynamic>))
            .toList();
        _punches = [
          for (final p in list)
            p.jobId.isEmpty
                ? () {
                    // 旧数据无工作归属：归入迁移工作
                    punchesMigrated = true;
                    return PunchRecord(
                      id: p.id,
                      dateKey: p.dateKey,
                      time: p.time,
                      isIn: p.isIn,
                      jobId: _migratedJobId,
                    );
                  }()
                : p,
        ];
      } catch (e) {
        debugPrint('打卡读取失败: $e');
      }
    }
    final markRaw = prefs.getString(_markKey);
    _marks = {};
    if (markRaw != null && markRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(markRaw);
        if (decoded is Map<String, dynamic>) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is! Map<String, dynamic>) continue;
            if (v.containsKey('type') || v.containsKey('isWork')) {
              // 旧格式：dateKey → 标记
              _marks[e.key] = {_migratedJobId: DayMark.fromJson(v)};
            } else {
              // 新格式：dateKey → jobId → 标记
              final byJob = {
                for (final j in v.entries)
                  if (j.value is Map<String, dynamic>)
                    j.key: DayMark.fromJson(j.value as Map<String, dynamic>),
              };
              if (byJob.isNotEmpty) _marks[e.key] = byJob;
            }
          }
        }
      } catch (e) {
        debugPrint('日期标记读取失败: $e');
      }
    }
    final otRaw = prefs.getString(_overtimeKey);
    _overtime = {};
    if (otRaw != null && otRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(otRaw);
        if (decoded is Map<String, dynamic>) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is num) {
              // 旧格式：dateKey → 小时
              if (v > 0) _overtime[e.key] = {_migratedJobId: v.toDouble()};
            } else if (v is Map<String, dynamic>) {
              final byJob = {
                for (final j in v.entries)
                  if ((j.value as num) > 0) j.key: (j.value as num).toDouble(),
              };
              if (byJob.isNotEmpty) _overtime[e.key] = byJob;
            }
          }
        }
      } catch (e) {
        debugPrint('加班记录读取失败: $e');
      }
    }
    final commissionRaw = prefs.getString(_commissionKey);
    _commissions = {};
    if (commissionRaw != null && commissionRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(commissionRaw);
        if (decoded is Map<String, dynamic>) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is num) {
              // 旧格式：yyyy-MM → 金额
              if (v > 0) _commissions[e.key] = {_migratedJobId: v.toDouble()};
            } else if (v is Map<String, dynamic>) {
              final byJob = {
                for (final j in v.entries)
                  if ((j.value as num) > 0) j.key: (j.value as num).toDouble(),
              };
              if (byJob.isNotEmpty) _commissions[e.key] = byJob;
            }
          }
        }
      } catch (e) {
        debugPrint('提成记录读取失败: $e');
      }
    }
    if (punchesMigrated) {
      await _persistPunches();
    }
    _loaded = true;
    notifyListeners();
  }

  /// 导入备份后重新加载全部记录。
  Future<void> reload() => _load();

  /// 各工作的跨天分割开关（jobId → 是否按午夜分割，未指定默认分割）。
  /// 由设置同步（main.dart 接线，来自各 Job.splitOvernight）。
  Map<String, bool> _jobSplits = {};

  /// 同步各工作的跨天分割开关（值变化时通知刷新）。
  void setJobSplits(Map<String, bool> values) {
    if (values.length == _jobSplits.length &&
        values.entries.every((e) => _jobSplits[e.key] == e.value)) {
      return;
    }
    _jobSplits = {...values};
    notifyListeners();
  }

  /// 某工作的跨天分割开关（默认分割）。
  bool _splitOf(String jobId) => _jobSplits[jobId] ?? true;

  Future<void> _persistPunches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _punchKey,
      jsonEncode([for (final p in _punches) p.toJson()]),
    );
  }

  Future<void> _persistMarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _markKey,
      jsonEncode({
        for (final e in _marks.entries)
          e.key: {for (final m in e.value.entries) m.key: m.value.toJson()},
      }),
    );
  }

  Future<void> _persistOvertime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_overtimeKey, jsonEncode(_overtime));
  }

  Future<void> _persistCommissions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_commissionKey, jsonEncode(_commissions));
  }

  // ---------- 打卡 ----------

  /// 某天的打卡记录，按时间排序。
  List<PunchRecord> punchesOf(String dateKey, {String? jobId}) => [
    for (final p in _punches)
      if (p.dateKey == dateKey && (jobId == null || p.jobId == jobId)) p,
  ]..sort((a, b) => a.time.compareTo(b.time));

  /// 某份工作（或全部）的打卡按时间排序。
  List<PunchRecord> _sortedPunches({String? jobId}) => [
    for (final p in _punches)
      if (jobId == null || p.jobId == jobId) p,
  ]..sort((a, b) => a.time.compareTo(b.time));

  /// 打卡记录中出现过的工作 id。
  Set<String> get _punchedJobIds => {for (final p in _punches) p.jobId};

  /// 全局配对的上班时段：下班卡闭合最近一次未闭合的上班卡，
  /// 不受自然日限制（跨天夜班：昨晚上班、今早下班也能闭合）。
  /// [jobId] 为空（全部）时各工作分别配对后合并，
  /// 避免多工作打卡交错时跨工作误配对。
  List<WorkSession> _rawSessions({String? jobId}) {
    if (jobId == null) {
      final merged = <WorkSession>[];
      for (final j in _punchedJobIds) {
        merged.addAll(_rawSessions(jobId: j));
      }
      merged.sort((a, b) => a.start.compareTo(b.start));
      return merged;
    }
    final sessions = <WorkSession>[];
    DateTime? open;
    for (final p in _sortedPunches(jobId: jobId)) {
      if (p.isIn) {
        open = p.time;
      } else if (open != null) {
        sessions.add(WorkSession(start: open, end: p.time));
        open = null;
      }
    }
    return sessions;
  }

  /// 当前未闭合的上班卡时间（进行中时段的起点）。
  DateTime? _openStartGlobal({String? jobId}) {
    DateTime? open;
    for (final p in _sortedPunches(jobId: jobId)) {
      if (p.isIn) {
        open = p.time;
      } else if (open != null) {
        open = null;
      }
    }
    return open;
  }

  /// 全部工作各自的未闭合上班卡时间（多工作可能同时进行中）。
  Set<DateTime> _allOpenStarts() {
    final opens = <DateTime>{};
    for (final j in _punchedJobIds) {
      final open = _openStartGlobal(jobId: j);
      if (open != null) opens.add(open);
    }
    return opens;
  }

  /// [end] 之前最近一次未被闭合的上班卡（用于定位跨天时段的上半段）。
  PunchRecord? _matchedInBefore(DateTime end, {String? jobId}) {
    PunchRecord? lastIn;
    for (final p in _sortedPunches(jobId: jobId)) {
      if (!p.time.isBefore(end)) break;
      if (p.isIn) {
        lastIn = p;
      } else if (lastIn != null) {
        lastIn = null;
      }
    }
    return lastIn;
  }

  /// 时间线补充显示的跨天上班卡：与本日时段配对但不属于本日
  ///（昨晚上班卡由今早下班卡闭合，或夜班进行中且本日尚无打卡）。
  /// 与 isWorkingToday 相同的 48 小时窗口：隔多日的忘打卡不补充显示。
  PunchRecord? carryOverIn(String dateKey, {String? jobId}) {
    final list = punchesOf(dateKey, jobId: jobId);
    if (list.isNotEmpty) {
      // 本日首笔为下班卡：其配对的上班卡属于前日，需补充显示
      //（按该下班卡所属工作配对，全部模式下不跨工作误配）
      return list.first.isIn
          ? null
          : _matchedInBefore(list.first.time, jobId: list.first.jobId);
    }
    // 本日无打卡：进行中的上班卡若属于前日（夜班延续），补充显示
    DateTime? open;
    String? openJobId;
    if (jobId == null) {
      for (final j in _punchedJobIds) {
        final o = _openStartGlobal(jobId: j);
        if (o != null && (open == null || o.isBefore(open))) {
          open = o;
          openJobId = j;
        }
      }
    } else {
      open = _openStartGlobal(jobId: jobId);
      openJobId = jobId;
    }
    if (open == null) return null;
    final day = dateOfKey(dateKey);
    final dayStart = DateTime(day.year, day.month, day.day);
    // 48 小时窗口：隔多日的忘打卡不再当作进行中的夜班
    if (open.isBefore(dayStart.subtract(const Duration(days: 1)))) {
      return null;
    }
    return open.isBefore(dayStart)
        ? _matchedInBefore(DateTime.now(), jobId: openJobId)
        : null;
  }

  /// 当前是否处于上班状态：最近一次打卡是未闭合的上班卡，
  /// 且不早于该天前一天（覆盖跨天夜班进行中；隔多日的忘打卡不算）。
  /// [jobId] 为空（全部）时任一工作进行中即算。
  bool isWorkingToday(String dateKey, {String? jobId}) {
    final day = dateOfKey(dateKey);
    final limit = DateTime(day.year, day.month, day.day).subtract(
      const Duration(days: 1),
    );
    bool working(DateTime open) => !open.isBefore(limit);
    if (jobId == null) return _allOpenStarts().any(working);
    final open = _openStartGlobal(jobId: jobId);
    return open != null && working(open);
  }

  /// 已闭合跨天时段的上班卡时间集合（不分割时这些卡归入下班日）。
  Set<DateTime> _crossDayStarts({String? jobId}) => {
    for (final s in _rawSessions(jobId: jobId))
      if (dayKeyOf(s.start) != dayKeyOf(s.end)) s.start,
  };

  /// 某天的上班时段：
  /// - 分割（默认）：跨天时段按午夜切分，工时分摊到覆盖的每一天
  ///   （超过 24 小时的打卡会分别计入多个出勤日）。
  /// - 不分割：跨天时段不切分，整段以下班卡日期为准归入下班日。
  /// [jobId] 为空（全部）时各工作按自己的分割口径分别计算后合并。
  List<WorkSession> sessionsOf(String dateKey, {String? jobId}) {
    if (jobId == null) {
      final merged = <WorkSession>[];
      for (final j in _punchedJobIds) {
        merged.addAll(sessionsOf(dateKey, jobId: j));
      }
      merged.sort((a, b) => a.start.compareTo(b.start));
      return merged;
    }
    final raw = _rawSessions(jobId: jobId);
    if (!_splitOf(jobId)) {
      return [
        for (final s in raw)
          if (dayKeyOf(s.end) == dateKey) s,
      ];
    }
    final day = dateOfKey(dateKey);
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return [
      for (final s in raw)
        if (s.end.isAfter(dayStart) && s.start.isBefore(dayEnd))
          WorkSession(
            start: s.start.isBefore(dayStart) ? dayStart : s.start,
            end: s.end.isAfter(dayEnd) ? dayEnd : s.end,
          ),
    ];
  }

  /// 某天上班总时长：已闭合时段（含跨天分摊/归下班日）+ 进行中的时段
  ///（仅对「今天」累计进行中时长，避免把「现在」误算进往日；
  /// 不分割时进行中的夜班从上班卡起算完整时长；
  /// [jobId] 为空（全部）时各工作按自己的分割口径分别累计）。
  Duration totalWorkTime(String dateKey, {String? jobId}) {
    final now = DateTime.now();
    final isToday = dateKey == dayKeyOf(now);
    final day = dateOfKey(dateKey);
    final dayStart = DateTime(day.year, day.month, day.day);
    final windowStart = dayStart.subtract(const Duration(days: 1));

    Duration ofJob(String j) {
      var total = sessionsOf(
        dateKey,
        jobId: j,
      ).fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
      if (!isToday) return total;
      final open = _openStartGlobal(jobId: j);
      if (open == null) return total;
      // 与 isWorkingToday 相同的 48 小时窗口：隔多日的忘打卡不算
      if (open.isBefore(windowStart)) return total;
      final from = open.isBefore(dayStart) && _splitOf(j) ? dayStart : open;
      return total + (now.isAfter(from) ? now.difference(from) : Duration.zero);
    }

    if (jobId != null) return ofJob(jobId);
    var total = Duration.zero;
    for (final j in _punchedJobIds) {
      total += ofJob(j);
    }
    return total;
  }

  /// 某天的打卡工时（小时）。今天含进行中的时段，往日只算已闭合时段
  /// （避免忘记打下班卡时把「现在」误算进往日）。
  double punchHoursOf(String dateKey, {String? jobId}) {
    final minutes = dateKey == dayKeyOf(DateTime.now())
        ? totalWorkTime(dateKey, jobId: jobId).inMinutes
        : sessionsOf(
            dateKey,
            jobId: jobId,
          ).fold<int>(0, (sum, s) => sum + s.duration.inMinutes);
    return minutes / 60.0;
  }

  // ---------- 日期标记与加班 ----------

  /// 某天某份工作的手工标记；[jobId] 为空返回任一工作的标记。
  DayMark? markOf(String dateKey, {String? jobId}) {
    final byJob = _marks[dateKey];
    if (byJob == null) return null;
    if (jobId != null) return byJob[jobId];
    for (final mark in byJob.values) {
      return mark;
    }
    return null;
  }

  /// 某天任一工作的标记是否满足 [test]。
  bool anyMark(String dateKey, bool Function(DayMark) test) =>
      _marks[dateKey]?.values.any(test) ?? false;

  /// 设置/清除某天某份工作的标记（null 为清除）。
  Future<void> setMark(String dateKey, DayMark? mark, {String? jobId}) async {
    final id = jobId ?? _migratedJobId;
    final byJob = {...?_marks[dateKey]};
    if (mark == null) {
      byJob.remove(id);
    } else {
      byJob[id] = mark;
    }
    if (byJob.isEmpty) {
      _marks.remove(dateKey);
    } else {
      _marks[dateKey] = byJob;
    }
    notifyListeners();
    await _persistMarks();
  }

  /// 回填忘打卡补记工作日的工时：日薪/月薪模式没有实际打卡工时，
  /// 按该工作的标准工时（如 09:00–21:00 → 12h）补齐，
  /// 让日历/当日明细显示的工时与正常打卡一致；计薪仍按整天计算。
  ///
  /// 仅处理「工时为空」的工作日标记；时薪模式由用户输入工时，不在此映射中。
  /// 幂等：没有需要回填的标记时不写盘。
  Future<void> backfillWorkMarkHours(
    Map<String, int> standardMinutesByJob,
  ) async {
    var changed = false;
    for (final byJob in _marks.values) {
      for (final entry in byJob.entries) {
        final mark = entry.value;
        if (!mark.isWork || mark.hours > 0) continue;
        final minutes = standardMinutesByJob[entry.key];
        if (minutes == null || minutes <= 0) continue;
        byJob[entry.key] = DayMark.work(minutes / 60);
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    await _persistMarks();
  }

  /// 某天某份工作的加班工时（小时）；[jobId] 为空返回全部工作合计。
  double overtimeOf(String dateKey, {String? jobId}) {
    final byJob = _overtime[dateKey];
    if (byJob == null) return 0;
    if (jobId != null) return byJob[jobId] ?? 0;
    return byJob.values.fold(0.0, (sum, v) => sum + v);
  }

  /// 设置/清除某天某份工作的加班工时（null 或 <=0 为清除）。
  Future<void> setOvertime(
    String dateKey,
    double? hours, {
    String? jobId,
  }) async {
    final id = jobId ?? _migratedJobId;
    final byJob = {...?_overtime[dateKey]};
    if (hours == null || hours <= 0) {
      byJob.remove(id);
    } else {
      byJob[id] = hours;
    }
    if (byJob.isEmpty) {
      _overtime.remove(dateKey);
    } else {
      _overtime[dateKey] = byJob;
    }
    notifyListeners();
    await _persistOvertime();
  }

  // ---------- 提成（按月录入） ----------

  /// 月键：yyyy-MM。
  static String monthKeyOf(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  /// 某月某份工作的提成金额；[jobId] 为空返回全部工作合计。
  double commissionOf(DateTime month, {String? jobId}) {
    final byJob = _commissions[monthKeyOf(month)];
    if (byJob == null) return 0;
    if (jobId != null) return byJob[jobId] ?? 0;
    return byJob.values.fold(0.0, (sum, v) => sum + v);
  }

  /// 设置/清除某月某份工作的提成（null 或 <=0 为清除）。
  Future<void> setCommission(
    DateTime month,
    double? amount, {
    String? jobId,
  }) async {
    final id = jobId ?? _migratedJobId;
    final key = monthKeyOf(month);
    final byJob = {...?_commissions[key]};
    if (amount == null || amount <= 0) {
      byJob.remove(id);
    } else {
      byJob[id] = amount;
    }
    if (byJob.isEmpty) {
      _commissions.remove(key);
    } else {
      _commissions[key] = byJob;
    }
    notifyListeners();
    await _persistCommissions();
  }

  /// 全部提成合计。
  double get commissionTotal => _commissions.values.fold(
    0,
    (sum, byJob) => sum + byJob.values.fold(0.0, (s, v) => s + v),
  );

  /// 某天是否出勤：有打卡或被手工标记为工作日。
  bool isWorkdayOn(String dateKey, {String? jobId}) {
    if (hasPunchedOn(dateKey, jobId: jobId)) return true;
    if (jobId == null) return anyMark(dateKey, (m) => m.isWork);
    return _marks[dateKey]?[jobId]?.isWork ?? false;
  }

  /// 某天的基本工时（小时，不含加班）：打卡工时或工作日标记工时。
  double baseHoursOf(String dateKey, {String? jobId}) {
    if (hasPunchedOn(dateKey, jobId: jobId)) {
      return punchHoursOf(dateKey, jobId: jobId);
    }
    final mark = markOf(dateKey, jobId: jobId);
    return mark != null && mark.isWork ? mark.hours : 0;
  }

  /// 某天的总工时（小时，含加班）。
  double dayHoursOf(String dateKey, {String? jobId}) =>
      baseHoursOf(dateKey, jobId: jobId) + overtimeOf(dateKey, jobId: jobId);

  /// 参与统计的日期（有打卡、标记或加班）。
  Set<String> _activeDateKeys({String? jobId}) => {
    for (final p in _punches)
      if (jobId == null || p.jobId == jobId) p.dateKey,
    for (final e in _marks.entries)
      if (jobId == null || e.value.containsKey(jobId)) e.key,
    for (final e in _overtime.entries)
      if (jobId == null || e.value.containsKey(jobId)) e.key,
  };

  /// 最早的数据日期（打卡/标记/加班中最早的一天）；无任何数据时返回 null。
  /// 用于判断「首次使用前」的日子：早于该日的过去日期视为无状态。
  DateTime? earliestDataDate({String? jobId}) {
    DateTime? earliest;
    for (final k in _activeDateKeys(jobId: jobId)) {
      final d = DateTime.tryParse(k);
      if (d == null) continue;
      if (earliest == null || d.isBefore(earliest)) earliest = d;
    }
    return earliest;
  }

  /// 时间范围内（按天，含边界）的基本工时（不含加班，时薪计薪基数）。
  double baseHoursBetween(DateTime start, DateTime end, {String? jobId}) {
    final from = dayKeyOf(start);
    final to = dayKeyOf(end);
    return _activeDateKeys(jobId: jobId)
        .where((k) => k.compareTo(from) >= 0 && k.compareTo(to) <= 0)
        .fold<double>(0, (sum, k) => sum + baseHoursOf(k, jobId: jobId));
  }

  /// 全部基本工时（不含加班）。
  double baseHoursAll({String? jobId}) => _activeDateKeys(
    jobId: jobId,
  ).fold<double>(0, (sum, k) => sum + baseHoursOf(k, jobId: jobId));

  /// 时间范围内（按天，含边界）的总工时（含加班）。
  double hoursBetween(DateTime start, DateTime end, {String? jobId}) {
    final from = dayKeyOf(start);
    final to = dayKeyOf(end);
    return _activeDateKeys(jobId: jobId)
        .where((k) => k.compareTo(from) >= 0 && k.compareTo(to) <= 0)
        .fold<double>(0, (sum, k) => sum + dayHoursOf(k, jobId: jobId));
  }

  /// 全部总工时（含加班）。
  double hoursAll({String? jobId}) => _activeDateKeys(
    jobId: jobId,
  ).fold<double>(0, (sum, k) => sum + dayHoursOf(k, jobId: jobId));

  /// 时间范围内的加班工时（小时）。start 为空表示全部。
  double overtimeHoursBetween({DateTime? start, DateTime? end, String? jobId}) {
    var total = 0.0;
    for (final e in _overtime.entries) {
      if (start != null) {
        final from = dayKeyOf(start);
        final to = dayKeyOf(end ?? start);
        if (e.key.compareTo(from) < 0 || e.key.compareTo(to) > 0) continue;
      }
      if (jobId != null) {
        total += e.value[jobId] ?? 0;
      } else {
        total += e.value.values.fold(0.0, (s, v) => s + v);
      }
    }
    return total;
  }

  /// 某天的自动加班工时（小时）：固定上下班时间开启自动加班后，
  /// 当日基本工时（打卡/标记，不含手动加班）超出标准工时的部分。
  double autoOvertimeOf(String dateKey, int standardMinutes, {String? jobId}) {
    final hours = baseHoursOf(dateKey, jobId: jobId);
    final std = standardMinutes / 60.0;
    return hours > std ? hours - std : 0;
  }

  /// 时间范围内（按天，含边界）的自动加班工时合计。start 为空表示全部。
  double autoOvertimeHours(
    int standardMinutes, {
    DateTime? start,
    DateTime? end,
    String? jobId,
  }) {
    final from = start == null ? null : dayKeyOf(start);
    final to = start == null ? null : dayKeyOf(end ?? start);
    var total = 0.0;
    for (final k in _activeDateKeys(jobId: jobId)) {
      if (from != null && (k.compareTo(from) < 0 || k.compareTo(to!) > 0)) {
        continue;
      }
      total += autoOvertimeOf(k, standardMinutes, jobId: jobId);
    }
    return total;
  }

  /// 某天是否有打卡记录。
  /// - 分割（默认）：跨天下班卡日按午夜分摊后有自己的工时，正常算作出勤日。
  /// - 不分割：跨天上班卡（已闭合或进行中）随时段一并归入下班日
  ///   （时间线亦显示在下班日），上班日当天不再算有效打卡。
  /// [jobId] 为空（全部）时任一工作当天有打卡即算。
  bool hasPunchedOn(String dateKey, {String? jobId}) {
    if (jobId == null) {
      for (final j in _punchedJobIds) {
        if (hasPunchedOn(dateKey, jobId: j)) return true;
      }
      return false;
    }
    if (_splitOf(jobId)) return punchesOf(dateKey, jobId: jobId).isNotEmpty;
    final carriedAway = _crossDayStarts(jobId: jobId);
    final openAway = _openCrossDayStarts(jobId: jobId);
    for (final p in punchesOf(dateKey, jobId: jobId)) {
      if (p.isIn) {
        // 已闭合/进行中的跨天上班卡均归入下班日，上班日不再算
        if (carriedAway.contains(p.time) || openAway.contains(p.time)) {
          continue;
        }
      }
      return true;
    }
    // 下班日吸收跨天上班卡：视为该日打卡记录
    for (final s in _rawSessions(jobId: jobId)) {
      if (dayKeyOf(s.start) != dateKey && dayKeyOf(s.end) == dateKey) {
        return true;
      }
    }
    return false;
  }

  /// 进行中的跨天上班卡时间集合（不分割时同样归入下班日，
  /// 上班日当天不再算有效打卡）。
  Set<DateTime> _openCrossDayStarts({String? jobId}) {
    final opens = <DateTime>{};
    if (jobId == null) {
      opens.addAll(_allOpenStarts());
    } else {
      final open = _openStartGlobal(jobId: jobId);
      if (open != null) opens.add(open);
    }
    final today = dayKeyOf(DateTime.now());
    return {
      for (final open in opens) if (dayKeyOf(open) != today) open,
    };
  }

  /// 时间范围内（按天，含边界）的出勤天数。
  int workedDaysBetween(DateTime start, DateTime end, {String? jobId}) {
    final from = dayKeyOf(start);
    final to = dayKeyOf(end);
    return _activeDateKeys(jobId: jobId)
        .where(
          (k) =>
              k.compareTo(from) >= 0 &&
              k.compareTo(to) <= 0 &&
              isWorkdayOn(k, jobId: jobId),
        )
        .length;
  }

  /// 全部出勤天数。
  int workedDaysAll({String? jobId}) => _activeDateKeys(
    jobId: jobId,
  ).where((k) => isWorkdayOn(k, jobId: jobId)).length;

  /// 日薪/月薪的计薪天数（单位：天）：
  /// - 有有效打卡：按闭合时段折算（与 baseHoursOf 口径一致，打卡优先于标记）
  /// - 无打卡：手工标记工作日 → 1 天；休息/请假 → 0
  /// - 打卡：必须已打下班卡（存在闭合时段）才计；闭合时长 ≥ 半个标准工时
  ///   为整天，否则半天；未闭合（含今天只打了上班卡）→ 0
  double dayUnitsOf(String dateKey, int standardMinutes, {String? jobId}) {
    if (hasPunchedOn(dateKey, jobId: jobId)) {
      final minutes = sessionsOf(
        dateKey,
        jobId: jobId,
      ).fold<int>(0, (sum, s) => sum + s.duration.inMinutes);
      if (minutes <= 0) return 0.0;
      return minutes * 2 >= standardMinutes ? 1.0 : 0.5;
    }
    final mark = markOf(dateKey, jobId: jobId);
    return mark != null && mark.isWork ? 1.0 : 0.0;
  }

  /// 范围内计薪天数总和（日薪/月薪口径）。start 为空表示全部。
  double paidDays({
    DateTime? start,
    DateTime? end,
    int standardMinutes = 540,
    String? jobId,
  }) {
    final from = start == null ? null : dayKeyOf(start);
    final to = start == null ? null : dayKeyOf(end ?? start);
    var total = 0.0;
    for (final k in _activeDateKeys(jobId: jobId)) {
      if (from != null && (k.compareTo(from) < 0 || k.compareTo(to!) > 0)) {
        continue;
      }
      total += dayUnitsOf(k, standardMinutes, jobId: jobId);
    }
    return total;
  }

  /// 时薪收入：范围内基本工时 × 时薪（加班另计）。start 为空表示全部。
  double hoursEarnings(
    double hourlyRate, {
    DateTime? start,
    DateTime? end,
    String? jobId,
  }) {
    final hours = start == null
        ? baseHoursAll(jobId: jobId)
        : baseHoursBetween(start, end ?? start, jobId: jobId);
    return hours * hourlyRate;
  }

  /// 固定工资收入：范围内出勤天数 × 日薪。start 为空表示全部。
  /// 日薪/月薪按 [dayUnitsOf] 计天数（打完下班卡才计，半天/整天）。
  double fixedEarnings(
    double dailyWage, {
    DateTime? start,
    DateTime? end,
    int standardMinutes = 540,
    String? jobId,
  }) {
    final days = paidDays(
      start: start,
      end: end,
      standardMinutes: standardMinutes,
      jobId: jobId,
    );
    return days * dailyWage;
  }

  /// 月薪折算收入：出勤天数 × 月薪 ÷ 21.75（平均月计薪天数）。
  /// byActualDays = true 时按每个出勤日所在月逐日折算，分母为该月
  /// 应出勤天数（[expectedWorkDaysOf] 回调提供，通常为当月总天数减
  /// 排班休息天数——排班休息日不扣钱，满勤即全额月薪；未提供时
  /// 回落当月总天数）。start 为空表示全部。
  double monthlyEarnings(
    double monthlySalary, {
    DateTime? start,
    DateTime? end,
    bool byActualDays = false,
    int Function(DateTime month)? expectedWorkDaysOf,
    int standardMinutes = 540,
    String? jobId,
  }) {
    if (!byActualDays) {
      final days = paidDays(
        start: start,
        end: end,
        standardMinutes: standardMinutes,
        jobId: jobId,
      );
      return days * monthlySalary / 21.75;
    }
    final from = start == null ? null : dayKeyOf(start);
    final to = start == null ? null : dayKeyOf(end ?? start);
    var total = 0.0;
    for (final k in _activeDateKeys(jobId: jobId)) {
      if (from != null && (k.compareTo(from) < 0 || k.compareTo(to!) > 0)) {
        continue;
      }
      final units = dayUnitsOf(k, standardMinutes, jobId: jobId);
      if (units <= 0) continue;
      final d = DateTime.tryParse(k);
      if (d == null) continue;
      // 所在月应出勤天数（排班休息不扣钱）；无效时回落当月总天数
      final daysInMonth = DateTime(d.year, d.month + 1, 0).day;
      final expected =
          expectedWorkDaysOf?.call(DateTime(d.year, d.month)) ?? daysInMonth;
      total += units * monthlySalary / (expected > 0 ? expected : daysInMonth);
    }
    return total;
  }

  /// 加班收入：范围内加班工时 × 加班时薪。start 为空表示全部。
  double overtimeEarnings(
    double overtimeRate, {
    DateTime? start,
    DateTime? end,
    String? jobId,
  }) {
    final hours = overtimeHoursBetween(start: start, end: end, jobId: jobId);
    return hours * overtimeRate;
  }

  Future<void> addPunch(bool isIn, {String? jobId}) =>
      addPunchAt(isIn, DateTime.now(), jobId: jobId);

  /// 以指定时间打卡（供测试与补录使用）。
  @visibleForTesting
  Future<void> addPunchAt(bool isIn, DateTime time, {String? jobId}) async {
    _punches = [
      ..._punches,
      PunchRecord(
        id: time.microsecondsSinceEpoch.toString(),
        dateKey: dayKeyOf(time),
        time: time,
        isIn: isIn,
        jobId: jobId ?? _migratedJobId,
      ),
    ];
    notifyListeners();
    await _persistPunches();
  }

  Future<void> undoLastPunch(String dateKey, {String? jobId}) async {
    final list = punchesOf(dateKey, jobId: jobId);
    if (list.isEmpty) return;
    final last = list.last;
    _punches = [
      for (final p in _punches)
        if (p.id != last.id) p,
    ];
    notifyListeners();
    await _persistPunches();
  }

  /// 简洁模式一键打卡：直接生成一条闭合时段（上班 + 下班）。
  /// 需保证 [start] 早于 [end]。
  Future<void> punchSession(
    DateTime start,
    DateTime end, {
    String? jobId,
  }) async {
    assert(start.isBefore(end));
    await addPunchAt(true, start, jobId: jobId);
    await addPunchAt(false, end, jobId: jobId);
  }

  /// 简洁模式撤销：移除最近一条闭合时段（下班卡 + 其闭合的上班卡，可能跨天）；
  /// 若最近的是进行中的上班卡，则仅移除该卡。
  Future<void> undoLastSession({String? jobId}) async {
    final j = jobId ?? _migratedJobId;
    final sorted = [
      for (final p in _punches)
        if (p.jobId == j) p,
    ]..sort((a, b) => a.time.compareTo(b.time));
    if (sorted.isEmpty) return;
    final last = sorted.last;
    final removedIds = <String>{last.id};
    if (!last.isIn) {
      // 下班卡：找其闭合的最近一张上班卡
      var found = false;
      for (var i = sorted.length - 2; i >= 0; i--) {
        if (sorted[i].isIn) {
          removedIds.add(sorted[i].id);
          found = true;
          break;
        }
      }
      if (!found) return; // 无对应上班卡：异常数据，不动
    }
    _punches = [
      for (final p in _punches)
        if (!removedIds.contains(p.id)) p,
    ];
    notifyListeners();
    await _persistPunches();
  }

  /// 删除某份工作的全部记录（打卡、标记、加班、提成）。
  Future<void> removeJob(String jobId) async {
    _punches = [
      for (final p in _punches)
        if (p.jobId != jobId) p,
    ];
    final marks = <String, Map<String, DayMark>>{};
    for (final e in _marks.entries) {
      final byJob = {
        for (final m in e.value.entries)
          if (m.key != jobId) m.key: m.value,
      };
      if (byJob.isNotEmpty) marks[e.key] = byJob;
    }
    _marks = marks;
    final overtime = <String, Map<String, double>>{};
    for (final e in _overtime.entries) {
      final byJob = {
        for (final j in e.value.entries)
          if (j.key != jobId) j.key: j.value,
      };
      if (byJob.isNotEmpty) overtime[e.key] = byJob;
    }
    _overtime = overtime;
    final commissions = <String, Map<String, double>>{};
    for (final e in _commissions.entries) {
      final byJob = {
        for (final j in e.value.entries)
          if (j.key != jobId) j.key: j.value,
      };
      if (byJob.isNotEmpty) commissions[e.key] = byJob;
    }
    _commissions = commissions;
    notifyListeners();
    await _persistPunches();
    await _persistMarks();
    await _persistOvertime();
    await _persistCommissions();
  }

  Future<void> clearAll() async {
    _punches = [];
    _marks = {};
    _overtime = {};
    _commissions = {};
    notifyListeners();
    await _persistPunches();
    await _persistMarks();
    await _persistOvertime();
    await _persistCommissions();
  }
}
