import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/app/theme/app_palette.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/settings/data/job.dart';

export 'package:xinji/features/settings/data/job.dart';

/// 统计页可配置组件。
enum StatsSection { total, periods, daily, calendar, monthly }

/// 全局设置 + 工作列表管理。
/// 薪资、上下班时间、休息日排班、跨天分割、打卡模式与个税按工作（Job）独立配置；
/// 货币符号、外观等为全局设置。
class SettingsController extends ChangeNotifier {
  SettingsController() {
    _load();
  }

  static const _keyCurrency = 'xinji.currency';
  static const _keyThemeMode = 'xinji.themeMode';
  static const _keyOledBlack = 'xinji.oledBlack';
  static const _keyAccent = 'xinji.accent';
  static const _keyRestColor = 'xinji.restColor';
  static const _keyLeaveColor = 'xinji.leaveColor';
  static const _keyOvertimeColor = 'xinji.overtimeColorIndex';
  static const _keyCalendarHours = 'xinji.calendarHours';
  static const _keyNavLabels = 'xinji.navBarLabels';
  static const _keyNavCircle = 'xinji.navBarCircle';
  static const _keyStatsOrder = 'xinji.statsOrder';
  static const _keyStatsHidden = 'xinji.statsHidden';
  static const _keyStatsWeekStart = 'xinji.statsWeekStart';
  static const _keyStatsMonthAnchor = 'xinji.statsMonthAnchor';
  static const _keyStatsYearAnchorMonth = 'xinji.statsYearAnchorMonth';
  static const _keyStatsYearAnchorDay = 'xinji.statsYearAnchorDay';
  static const _keyStatsTotalStart = 'xinji.statsTotalStart';
  static const _keyJobs = 'xinji.jobs';
  static const _keyActiveJob = 'xinji.activeJobId';

  // 旧版全局键（跨天分割/打卡模式/打卡提醒/个税）：仅用于一次性迁移到各工作。
  static const _legacyKeySplit = 'xinji.splitOvernight';
  static const _legacyKeyPunchMode = 'xinji.punchMode';
  static const _legacyKeyPunchReminders = 'xinji.punchReminders';
  static const _legacyKeyTaxEnabled = 'xinji.taxEnabled';
  static const _legacyKeyTaxThreshold = 'xinji.taxThreshold';
  static const _legacyKeyTaxRate = 'xinji.taxRate';

  String _currency = '¥';
  ThemeMode _themeMode = ThemeMode.system;

  /// 深色模式是否使用纯黑背景（OLED 省电）。
  bool _oledBlack = false;
  Color _accent = AppPalette.brand;
  Color _restColor = AppPalette.defaultRestColor;
  Color _leaveColor = AppPalette.defaultLeaveColor;

  /// 加班日标记色索引（AppPalette.overtimeColors；-1 跟随主题加深）。
  int _overtimeColorIndex = -1;
  bool _calendarShowsHours = false;
  bool _navBarLabels = false;
  bool _navBarCircle = false;

  /// 统计页组件顺序（包含隐藏项，保持相对顺序）与隐藏集合。
  List<StatsSection> _statsOrder = StatsSection.values.toList();
  final Set<StatsSection> _statsHidden = {};

  /// 统计周期锚点：
  /// - 本周：每周起始日（1=周一 … 7=周日）
  /// - 本月：每月循环起始日（1~31，短月按月末处理）
  /// - 今年：年度循环起始（月、日）
  /// - 累计：起始统计日期（null = 全部数据）
  int _statsWeekStart = 1;
  int _statsMonthAnchorDay = 1;
  int _statsYearAnchorMonth = 1;
  int _statsYearAnchorDay = 1;
  DateTime? _statsTotalStart;

  /// 工作列表与当前选中工作（今日页打卡归属）。
  List<Job> _jobs = [];
  String? _activeJobId;

  /// 是否已从持久化加载完成。
  bool _loaded = false;
  bool get loaded => _loaded;

  List<Job> get jobs => List.unmodifiable(_jobs);

  Job? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  /// 当前选中工作 id；列表为空时为 null。
  String? get activeJobId {
    if (_jobs.isEmpty) return null;
    if (_activeJobId != null && jobById(_activeJobId!) != null) {
      return _activeJobId;
    }
    return _jobs.first.id;
  }

  /// 当前选中工作。
  Job? get activeJob {
    final id = activeJobId;
    return id == null ? null : jobById(id);
  }

  String get currency => _currency;
  ThemeMode get themeMode => _themeMode;

  /// 深色模式是否使用纯黑背景（OLED 省电）。
  bool get oledBlack => _oledBlack;
  Color get accent => _accent;
  Color get restColor => _restColor;
  Color get leaveColor => _leaveColor;

  /// 加班日标记色索引（-1 跟随主题加深）。
  int get overtimeColorIndex => _overtimeColorIndex;

  /// 日历单元格显示工时（true）或当日工资（false）。
  bool get calendarShowsHours => _calendarShowsHours;

  /// 底部导航是否显示文字标签（false 为 Streak 风格仅图标）。
  bool get navBarLabels => _navBarLabels;

  /// 底部导航激活色块是否为圆形（false 为圆角方块）。
  bool get navBarCircle => _navBarCircle;

  /// 统计页组件顺序（含隐藏项，保持相对顺序）。
  List<StatsSection> get statsOrder => List.unmodifiable(_statsOrder);

  /// 统计页可见组件（按顺序排列）。
  List<StatsSection> get visibleStatsSections =>
      _statsOrder.where((s) => !_statsHidden.contains(s)).toList();

  /// 统计页组件是否显示。
  bool statsSectionVisible(StatsSection section) =>
      !_statsHidden.contains(section);

  /// 是否为简洁打卡模式（一键打卡）：当前选中工作的打卡模式。
  bool get simplePunch => activeJob?.punchMode == 1;

  /// 统计周期锚点：本周起始日（1=周一 … 7=周日）。
  int get statsWeekStart => _statsWeekStart;

  /// 统计周期锚点：本月每月循环起始日（1~31）。
  int get statsMonthAnchorDay => _statsMonthAnchorDay;

  /// 统计周期锚点：今年年度循环起始月。
  int get statsYearAnchorMonth => _statsYearAnchorMonth;

  /// 统计周期锚点：今年年度循环起始日。
  int get statsYearAnchorDay => _statsYearAnchorDay;

  /// 统计累计起始日期（null = 全部数据）。
  DateTime? get statsTotalStart => _statsTotalStart;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _currency = prefs.getString(_keyCurrency) ?? '¥';
    final mode = prefs.getInt(_keyThemeMode);
    _themeMode = switch (mode) {
      1 => ThemeMode.light,
      2 => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _oledBlack = prefs.getBool(_keyOledBlack) ?? false;
    final accentValue = prefs.getInt(_keyAccent);
    if (accentValue != null &&
        accentValue >= 0 &&
        accentValue < AppPalette.accentColors.length) {
      _accent = AppPalette.accentColors[accentValue];
    }
    final restValue = prefs.getInt(_keyRestColor);
    if (restValue != null &&
        restValue >= 0 &&
        restValue < AppPalette.restColors.length) {
      _restColor = AppPalette.restColors[restValue];
    }
    final leaveValue = prefs.getInt(_keyLeaveColor);
    if (leaveValue != null &&
        leaveValue >= 0 &&
        leaveValue < AppPalette.leaveColors.length) {
      _leaveColor = AppPalette.leaveColors[leaveValue];
    }
    final overtimeColorValue = prefs.getInt(_keyOvertimeColor);
    if (overtimeColorValue != null &&
        overtimeColorValue >= -1 &&
        overtimeColorValue < AppPalette.overtimeColors.length) {
      _overtimeColorIndex = overtimeColorValue;
    }
    _calendarShowsHours = prefs.getBool(_keyCalendarHours) ?? false;
    _navBarLabels = prefs.getBool(_keyNavLabels) ?? false;
    _navBarCircle = prefs.getBool(_keyNavCircle) ?? false;
    final statsOrderRaw = prefs.getStringList(_keyStatsOrder);
    if (statsOrderRaw != null) {
      final byName = StatsSection.values.asNameMap();
      final parsed = statsOrderRaw
          .map((name) => byName[name])
          .whereType<StatsSection>()
          .toList();
      // 顺序表必须覆盖全部组件：新组件/被清掉的项追加到末尾
      for (final s in StatsSection.values) {
        if (!parsed.contains(s)) parsed.add(s);
      }
      _statsOrder = parsed;
    }
    final statsHiddenRaw = prefs.getStringList(_keyStatsHidden);
    if (statsHiddenRaw != null) {
      final byName = StatsSection.values.asNameMap();
      _statsHidden
        ..clear()
        ..addAll(
          statsHiddenRaw.map((name) => byName[name]).whereType<StatsSection>(),
        );
    }
    final weekStart = prefs.getInt(_keyStatsWeekStart);
    _statsWeekStart =
        weekStart != null && weekStart >= 1 && weekStart <= 7 ? weekStart : 1;
    final monthAnchor = prefs.getInt(_keyStatsMonthAnchor);
    _statsMonthAnchorDay =
        monthAnchor != null && monthAnchor >= 1 && monthAnchor <= 31
        ? monthAnchor
        : 1;
    final ym = prefs.getInt(_keyStatsYearAnchorMonth);
    _statsYearAnchorMonth =
        ym != null && ym >= 1 && ym <= 12 ? ym : 1;
    final yd = prefs.getInt(_keyStatsYearAnchorDay);
    _statsYearAnchorDay = yd != null && yd >= 1 && yd <= 31 ? yd : 1;
    _statsTotalStart = DateTime.tryParse(
      prefs.getString(_keyStatsTotalStart) ?? '',
    );

    // 工作列表：首次启动（无 xinji.jobs）时把旧版全局薪资设置迁移为「默认工作」。
    final jobsRaw = prefs.getString(_keyJobs);
    var jobs = <Job>[];
    if (jobsRaw != null && jobsRaw.isNotEmpty) {
      try {
        final list = jsonDecode(jobsRaw) as List;
        jobs = [for (final e in list) Job.fromJson(e as Map<String, dynamic>)];
      } catch (_) {}
    }
    if (jobs.isEmpty) {
      jobs = [_legacyJob(prefs)];
    }
    // 旧数据无标识色：按位置从色板轮选补齐，并立即持久化
    var colorsFixed = false;
    jobs = [
      for (final (i, job) in jobs.indexed)
        job.colorIndex < 0
            ? () {
                colorsFixed = true;
                return job.copyWith(
                  colorIndex: i % AppPalette.jobColors.length,
                );
              }()
            : job,
    ];
    _jobs = jobs;
    _activeJobId = prefs.getString(_keyActiveJob);
    if (jobById(_activeJobId ?? '') == null) {
      _activeJobId = _jobs.first.id;
    }
    // 一次性迁移：旧版全局的跨天分割/打卡模式/打卡提醒/个税设置应用到全部工作，
    // 随后清除旧键（之后各工作独立保存，不再被旧值覆盖）。
    var legacyApplied = false;
    final legacySplit = prefs.getBool(_legacyKeySplit);
    final legacyPunchMode = prefs.getInt(_legacyKeyPunchMode);
    final legacyPunchReminders = prefs.getBool(_legacyKeyPunchReminders);
    final legacyTaxEnabled = prefs.getBool(_legacyKeyTaxEnabled);
    // 容错读取：兼容 int/num 存储的旧值
    double? readDouble(String key) {
      final v = prefs.get(key);
      return v is num ? v.toDouble() : null;
    }

    final legacyTaxThreshold = readDouble(_legacyKeyTaxThreshold);
    final legacyTaxRate = readDouble(_legacyKeyTaxRate);
    if (legacySplit != null ||
        legacyPunchMode != null ||
        legacyPunchReminders != null ||
        legacyTaxEnabled != null ||
        legacyTaxThreshold != null ||
        legacyTaxRate != null) {
      legacyApplied = true;
      _jobs = [
        for (final job in _jobs)
          job.copyWith(
            splitOvernight: legacySplit ?? job.splitOvernight,
            punchMode: legacyPunchMode == null
                ? job.punchMode
                : (legacyPunchMode == 1 ? 1 : 2),
            punchReminders: legacyPunchReminders ?? job.punchReminders,
            taxEnabled: legacyTaxEnabled ?? job.taxEnabled,
            taxThreshold: legacyTaxThreshold ?? job.taxThreshold,
            taxRate: legacyTaxRate != null && legacyTaxRate > 0 &&
                    legacyTaxRate < 1
                ? legacyTaxRate
                : job.taxRate,
          ),
      ];
      await prefs.remove(_legacyKeySplit);
      await prefs.remove(_legacyKeyPunchMode);
      await prefs.remove(_legacyKeyPunchReminders);
      await prefs.remove(_legacyKeyTaxEnabled);
      await prefs.remove(_legacyKeyTaxThreshold);
      await prefs.remove(_legacyKeyTaxRate);
    }
    if (jobsRaw == null || colorsFixed || legacyApplied) {
      // 首次迁移/颜色补齐/旧全局设置迁移：立即持久化工作列表
      await _saveJobs(prefs);
    }
    _loaded = true;
    notifyListeners();
  }

  /// 从旧版全局薪资键构造迁移工作（id 固定为 job1，旧记录迁移时归入该 id）。
  Job _legacyJob(SharedPreferences prefs) {
    final modeIndex = prefs.getInt('xinji.calcMode') ?? 0;
    final calcMode = modeIndex >= 0 && modeIndex < CalcMode.values.length
        ? CalcMode.values[modeIndex]
        : CalcMode.hourly;
    final restIndex = prefs.getInt('xinji.restMode');
    final restMode = restIndex != null && restIndex >= 0 && restIndex <= 2
        ? RestSchedule.values[restIndex]
        : RestSchedule.flexible;
    Set<int>? fixedRest;
    final fixedRaw = prefs.getString('xinji.fixedRest');
    if (fixedRaw != null && fixedRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(fixedRaw) as List)
            .map((e) => e as int)
            .where((w) => w >= 1 && w <= 7)
            .toSet();
        if (list.isNotEmpty) fixedRest = list;
      } catch (_) {}
    }
    DateTime? anchor;
    final anchorRaw = prefs.getString('xinji.altAnchor');
    if (anchorRaw != null && anchorRaw.length == 10) {
      final y = int.tryParse(anchorRaw.substring(0, 4));
      final m = int.tryParse(anchorRaw.substring(5, 7));
      final d = int.tryParse(anchorRaw.substring(8, 10));
      if (y != null && m != null && d != null) anchor = DateTime(y, m, d);
    }
    return Job(
      id: 'job1',
      name: '默认工作',
      calcMode: calcMode,
      hourlyRate: prefs.getDouble('xinji.hourlyRate') ?? 20,
      dailyWage: prefs.getDouble('xinji.dailyWage') ?? 200,
      monthlySalary: prefs.getDouble('xinji.monthlySalary') ?? 5000,
      monthlyByActualDays: prefs.getBool('xinji.monthlyByActualDays') ?? false,
      overtimeRate: prefs.getDouble('xinji.overtimeRate') ?? 30,
      workStart: prefs.getInt('xinji.workStart') ?? 540,
      workEnd: prefs.getInt('xinji.workEnd') ?? 1080,
      restMode: restMode,
      fixedRestWeekdays: fixedRest,
      altAnchorMonday: anchor,
      altAnchorIsBig: prefs.getBool('xinji.altIsBig') ?? false,
    );
  }

  /// 导入备份后重新加载全部设置。
  Future<void> reload() => _load();

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, _currency);
    await prefs.setInt(_keyThemeMode, _themeMode.index);
    await prefs.setBool(_keyOledBlack, _oledBlack);
    final accentIndex = AppPalette.accentColors.indexOf(_accent);
    await prefs.setInt(_keyAccent, accentIndex == -1 ? 0 : accentIndex);
    final restIndex = AppPalette.restColors.indexOf(_restColor);
    await prefs.setInt(_keyRestColor, restIndex == -1 ? 0 : restIndex);
    final leaveIndex = AppPalette.leaveColors.indexOf(_leaveColor);
    await prefs.setInt(_keyLeaveColor, leaveIndex == -1 ? 0 : leaveIndex);
    await prefs.setInt(_keyOvertimeColor, _overtimeColorIndex);
    await prefs.setBool(_keyCalendarHours, _calendarShowsHours);
    await prefs.setBool(_keyNavLabels, _navBarLabels);
    await prefs.setBool(_keyNavCircle, _navBarCircle);
    await prefs.setStringList(
      _keyStatsOrder,
      _statsOrder.map((s) => s.name).toList(),
    );
    await prefs.setStringList(
      _keyStatsHidden,
      _statsHidden.map((s) => s.name).toList(),
    );
    await prefs.setInt(_keyStatsWeekStart, _statsWeekStart);
    await prefs.setInt(_keyStatsMonthAnchor, _statsMonthAnchorDay);
    await prefs.setInt(_keyStatsYearAnchorMonth, _statsYearAnchorMonth);
    await prefs.setInt(_keyStatsYearAnchorDay, _statsYearAnchorDay);
    await prefs.setString(
      _keyStatsTotalStart,
      _statsTotalStart == null
          ? ''
          : dayKeyOf(_statsTotalStart!),
    );
    await _saveJobs(prefs);
  }

  Future<void> _saveJobs(SharedPreferences prefs) async {
    await prefs.setString(
      _keyJobs,
      jsonEncode([for (final j in _jobs) j.toJson()]),
    );
    final active = activeJobId;
    if (active != null) {
      await prefs.setString(_keyActiveJob, active);
    }
  }

  // ---------- 工作管理 ----------

  /// 新增一份工作（默认参数，创建后设为当前选中；标识色按顺序轮选）。
  Future<Job> addJob() async {
    final used = {for (final j in _jobs) j.colorIndex};
    var colorIndex = 0;
    while (used.contains(colorIndex) &&
        colorIndex < AppPalette.jobColors.length) {
      colorIndex++;
    }
    final job = Job(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '工作 ${_jobs.length + 1}',
      colorIndex: colorIndex,
    );
    _jobs = [..._jobs, job];
    _activeJobId = job.id;
    notifyListeners();
    await _save();
    return job;
  }

  /// 草稿工作 id：新增工作流程中尚未点「完成」确认的工作（仅内存，不持久化）。
  String? _draftJobId;

  /// 新增工作（草稿）：先创建进入编辑，点「完成」才保存，中途返回则丢弃。
  Job createDraftJob() {
    final used = {for (final j in _jobs) j.colorIndex};
    var colorIndex = 0;
    while (used.contains(colorIndex) &&
        colorIndex < AppPalette.jobColors.length) {
      colorIndex++;
    }
    final job = Job(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '工作 ${_jobs.length + 1}',
      colorIndex: colorIndex,
    );
    _jobs = [..._jobs, job];
    _draftJobId = job.id;
    _activeJobId = job.id;
    notifyListeners();
    return job;
  }

  /// 完成新增：持久化草稿工作。
  Future<void> commitDraftJob() async {
    _draftJobId = null;
    notifyListeners();
    await _save();
  }

  /// 取消新增：丢弃草稿工作（不保存）。
  void discardDraftJob() {
    final id = _draftJobId;
    _draftJobId = null;
    if (id == null) return;
    _jobs = [
      for (final j in _jobs)
        if (j.id != id) j,
    ];
    if (_activeJobId == id || jobById(_activeJobId ?? '') == null) {
      _activeJobId = _jobs.isEmpty ? null : _jobs.first.id;
    }
    notifyListeners();
  }

  /// 更新一份工作（按 id 替换）；草稿工作仅更新内存，待「完成」时一并保存。
  Future<void> updateJob(Job job) async {
    _jobs = [for (final j in _jobs) j.id == job.id ? job : j];
    notifyListeners();
    if (_draftJobId != job.id) await _save();
  }

  /// 删除一份工作（其打卡等记录由 RecordsController.removeJob 清理）。
  /// 不允许删除最后一份工作。
  Future<void> removeJob(String id) async {
    if (_jobs.length <= 1) return;
    _jobs = [
      for (final j in _jobs)
        if (j.id != id) j,
    ];
    if (_activeJobId == id || jobById(_activeJobId ?? '') == null) {
      _activeJobId = _jobs.isEmpty ? null : _jobs.first.id;
    }
    notifyListeners();
    await _save();
  }

  /// 设置当前选中工作（今日页打卡归属）。
  Future<void> setActiveJobId(String id) async {
    if (jobById(id) == null) return;
    _activeJobId = id;
    notifyListeners();
    await _save();
  }

  /// 某天是否为「全部工作」的排班休息日（每份工作都休息）。
  bool isScheduledRestAll(DateTime day) =>
      _jobs.isNotEmpty && _jobs.every((job) => job.isScheduledRest(day));

  // ---------- 全局设置 ----------

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    notifyListeners();
    await _save();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _save();
  }

  /// 设置深色模式纯黑背景（OLED）。
  Future<void> setOledBlack(bool value) async {
    _oledBlack = value;
    notifyListeners();
    await _save();
  }

  Future<void> setAccent(Color color) async {
    _accent = color;
    notifyListeners();
    await _save();
  }

  Future<void> setRestColor(Color color) async {
    _restColor = color;
    notifyListeners();
    await _save();
  }

  Future<void> setLeaveColor(Color color) async {
    _leaveColor = color;
    notifyListeners();
    await _save();
  }

  /// 设置加班日标记色索引（-1 跟随主题加深）。
  Future<void> setOvertimeColorIndex(int index) async {
    if (index < -1 || index >= AppPalette.overtimeColors.length) return;
    _overtimeColorIndex = index;
    notifyListeners();
    await _save();
  }

  /// 日历单元格显示工时（true）或当日工资（false）。
  Future<void> setCalendarShowsHours(bool value) async {
    _calendarShowsHours = value;
    notifyListeners();
    await _save();
  }

  /// 底部导航是否显示文字标签。
  Future<void> setNavBarLabels(bool value) async {
    _navBarLabels = value;
    notifyListeners();
    await _save();
  }

  /// 底部导航激活色块是否为圆形。
  Future<void> setNavBarCircle(bool value) async {
    _navBarCircle = value;
    notifyListeners();
    await _save();
  }

  /// 设置统计页组件排列顺序（漏掉的组件自动追加到末尾）。
  Future<void> setStatsOrder(List<StatsSection> order) async {
    final next = [...order];
    for (final s in StatsSection.values) {
      if (!next.contains(s)) next.add(s);
    }
    _statsOrder = next;
    notifyListeners();
    await _save();
  }

  /// 显示/隐藏统计页组件。
  Future<void> setStatsSectionVisible(
    StatsSection section,
    bool visible,
  ) async {
    if (visible) {
      _statsHidden.remove(section);
    } else {
      _statsHidden.add(section);
    }
    notifyListeners();
    await _save();
  }

  /// 设置统计周期锚点：本周起始日（1=周一 … 7=周日）。
  Future<void> setStatsWeekStart(int weekday) async {
    if (weekday < 1 || weekday > 7) return;
    _statsWeekStart = weekday;
    notifyListeners();
    await _save();
  }

  /// 设置统计周期锚点：本月每月循环起始日（1~31）。
  Future<void> setStatsMonthAnchorDay(int day) async {
    if (day < 1 || day > 31) return;
    _statsMonthAnchorDay = day;
    notifyListeners();
    await _save();
  }

  /// 设置统计周期锚点：今年年度循环起始（月、日）。
  Future<void> setStatsYearAnchor(int month, int day) async {
    if (month < 1 || month > 12 || day < 1 || day > 31) return;
    _statsYearAnchorMonth = month;
    _statsYearAnchorDay = day;
    notifyListeners();
    await _save();
  }

  /// 设置统计累计起始日期（null = 全部数据）。
  Future<void> setStatsTotalStart(DateTime? date) async {
    _statsTotalStart = date == null
        ? null
        : DateTime(date.year, date.month, date.day);
    notifyListeners();
    await _save();
  }
}
