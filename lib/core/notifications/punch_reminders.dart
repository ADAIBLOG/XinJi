import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:xinji/core/notifications/reminder_schedule.dart';
import 'package:xinji/core/utils/day_key.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

/// 打卡提醒（每日定时通知）：每份工作独立开关与自定义时间点列表。
///
/// 双通道设计：
/// - **系统闹钟**：zonedSchedule + matchDateTimeComponents（每日重复）注册到
///   系统 AlarmManager，应用被杀/重启后仍可到点弹出；开机后由插件的
///   BootReceiver 自动恢复。重复触发复用同一个通知 id，不会越积越多。
/// - **应用内补发**：部分 ROM（如 MIUI）会拦截/延迟第三方闹钟，且错过的
///   通知不会补——因此应用运行期间每 30 秒检查一次，只补发
///   [reminderCatchUpWindow]（15 分钟）内到点、且当天尚未发出的提醒；
///   更早的错过提醒直接放过，避免深夜打开应用时一次刷出多条过期通知。
///
/// 去重：系统通知栏中同 id 已存在 + 当日已发记录（持久化到本地，重启后仍
/// 有效）。排定通知使用独立载荷与渠道，重排时只清理本功能的过期通知，
/// 不会误删其它通知。
class PunchReminders {
  PunchReminders._();

  static const _channelId = 'punch_reminders_v2';
  static const _channelName = '打卡提醒';
  static const _channelDescription = '上下班时间到点提醒打卡';

  /// 旧渠道（v1.39.4 及以前）：其重要性/横幅开关一旦创建便无法由应用提升，
  /// 启动时迁移到 [_channelId] 并以 MAX 重要性重建，恢复悬浮（横幅）通知。
  static const _legacyChannelIds = ['punch_reminders'];
  static const _icon = 'ic_stat_notify';
  static const _notificationTitle = '打卡提醒';
  static const _firedPrefsKey = 'xinji.remindersFired';
  static const _permissionAskedKey = 'xinji.remindersPermissionAsked';
  static const _checkInterval = Duration(seconds: 30);
  static const _rescheduleDebounce = Duration(milliseconds: 400);

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void>? _initFuture;
  static bool _tzReady = false;
  static bool _observerRegistered = false;

  /// 应用内补发定时器（仅在存在开启提醒的工作时运行）。
  static Timer? _timer;
  static Timer? _debounceTimer;
  static SettingsController? _settings;

  static bool _checking = false;
  static bool _applying = false;
  static bool _dirty = false;
  static bool _promptPermission = false;
  static String? _appliedSignature;

  /// 当日已发记录（dayKey|jobId|minute），持久化以防重启后重复补发。
  static final Set<String> _fired = {};
  static bool _firedLoaded = false;

  static DateTime? _lastPermissionWarning;

  /// 点击打卡提醒（通知本体或「去打卡」按钮）后的回调。
  /// 由 HomeShell 注册，用于回到「今日」页。
  static VoidCallback? onReminderTapped;

  /// 初始化插件（幂等）：时区数据库 + 通知渠道（Importance.max，
  /// 渠道先于任何调度存在）。
  static Future<void> init() {
    final existing = _initFuture;
    if (existing != null) return existing;
    // 失败时清空缓存，下次调用可重试（提醒功能失败不影响应用使用）。
    final future = _initialize().catchError((Object error) {
      debugPrint('[打卡提醒] 初始化失败: $error');
      _initFuture = null;
    });
    _initFuture = future;
    return future;
  }

  static Future<void> _initialize() async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    final android = _android;
    if (android != null) {
      // 迁移旧渠道：通知渠道的重要性创建后无法由应用提升，旧渠道若被设为
      // 低重要性或关闭横幅，就会出现「只有声音、下拉才看到通知」。
      for (final legacyId in _legacyChannelIds) {
        try {
          await android.deleteNotificationChannel(channelId: legacyId);
        } catch (e) {
          debugPrint('[打卡提醒] 删除旧通知渠道失败: $e');
        }
      }
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
    // 旧版本排定的通知没有载荷：启动时清掉，避免升级后仍弹出旧文案。
    // 旧渠道的活跃通知也会在此后重排时被同一 id 覆盖。
    await _cancelLegacyPending();
    await _cancelLegacyChannelActive();
    await _loadFired();
    if (!_observerRegistered) {
      WidgetsBinding.instance.addObserver(_ReminderLifecycleObserver());
      _observerRegistered = true;
    }
  }

  // ---------- 权限与系统设置 ----------

  /// 请求通知权限（Android 13+；已授权时为空操作）。
  static Future<bool> requestPermission() async {
    await init();
    await _markPermissionAsked();
    try {
      final granted = await _android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('[打卡提醒] 请求通知权限失败: $e');
      return false;
    }
  }

  /// 应用级通知权限是否已开启。
  static Future<bool> notificationsEnabled() async {
    await init();
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (e) {
      debugPrint('[打卡提醒] 查询通知权限失败: $e');
      return false;
    }
  }

  /// 已授权时直接返回 true，否则弹出系统授权请求。
  static Future<bool> ensurePermission() async {
    if (await notificationsEnabled()) return true;
    return requestPermission();
  }

  /// 是否允许精确闹钟（Android 12+ 的「闹钟和提醒」特殊权限）。
  static Future<bool> canScheduleExact() async {
    await init();
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('[打卡提醒] 查询精确闹钟权限失败: $e');
      return false;
    }
  }

  /// 跳转到系统「闹钟和提醒」授权页。
  static Future<bool> requestExactAlarmsPermission() async {
    await init();
    try {
      return await _android?.requestExactAlarmsPermission() ?? false;
    } catch (e) {
      debugPrint('[打卡提醒] 请求精确闹钟权限失败: $e');
      return false;
    }
  }

  /// 打开发送通知的系统设置页。
  static Future<void> openNotificationSettings() async {
    await init();
    try {
      await _plugin.openAppNotificationSettings();
    } catch (e) {
      debugPrint('[打卡提醒] 打开系统通知设置失败: $e');
    }
  }

  /// 与原生通信的电池优化通道。
  static const MethodChannel _powerChannel = MethodChannel(
    'com.adai.xinji/power',
  );

  /// 是否已加入电池优化白名单（未加入时部分系统会冻结后台闹钟）。
  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _powerChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? true;
    } catch (e) {
      // 查询失败时不误报（非 Android/测试环境），交由页面提示自行检查
      debugPrint('[打卡提醒] 查询电池优化状态失败: $e');
      return true;
    }
  }

  /// 申请加入电池优化白名单（系统弹窗或跳转应用信息页）。
  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _powerChannel.invokeMethod<void>(
        'requestIgnoreBatteryOptimizations',
      );
    } catch (e) {
      debugPrint('[打卡提醒] 请求电池优化白名单失败: $e');
    }
  }

  /// 已排定的本功能系统提醒数量。
  static Future<int> pendingReminderCount() async {
    await init();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending
          .where((request) => isReminderPayload(request.payload))
          .length;
    } catch (e) {
      debugPrint('[打卡提醒] 查询系统排定失败: $e');
      return 0;
    }
  }

  /// 通知渠道状态：重要性决定能否显示横幅（悬浮）通知。
  static Future<ReminderChannelStatus> channelStatus() async {
    await init();
    try {
      final channels = await _android?.getNotificationChannels();
      for (final channel in channels ?? const <AndroidNotificationChannel>[]) {
        if (channel.id != _channelId) continue;
        final importance = channel.importance;
        final label = switch (importance) {
          Importance.max || Importance.high => '重要性高，支持横幅/悬浮通知',
          Importance.defaultImportance => '重要性默认，可能没有横幅',
          Importance.low || Importance.min => '重要性低，可能无声音/横幅',
          Importance.none => '已被关闭（无通知）',
          _ => '重要性未知',
        };
        return ReminderChannelStatus(
          exists: true,
          headsUp: importance.value >= Importance.high.value,
          label: label,
        );
      }
    } catch (e) {
      debugPrint('[打卡提醒] 查询通知渠道失败: $e');
    }
    return const ReminderChannelStatus(
      exists: false,
      headsUp: false,
      label: '渠道尚未创建，开启提醒后会自动创建',
    );
  }

  // ---------- 排定 ----------

  /// 按设置重排提醒（幂等、去抖、串行）：
  /// 1. 把开启提醒工作的全部时间点注册为系统级每日通知；
  /// 2. 维护应用内补发定时器。
  ///
  /// 设置变化后调用即可。只有提醒相关配置真正变化时才触发平台调用；
  /// 短时间内连续变化会合并成一次，避免并发重排产生竞态。
  /// [force] 为 true 时忽略配置签名强制重排（如刚授予精确闹钟权限）。
  /// [promptPermission] 为 true 时在重排前请求通知权限（仅在用户主动开启
  /// 提醒时使用，避免启动时无故弹窗）。
  static void reschedule(
    SettingsController settings, {
    bool force = false,
    bool promptPermission = false,
  }) {
    if (!settings.loaded) return;
    _settings = settings;
    if (force) _appliedSignature = null;
    if (promptPermission) _promptPermission = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_rescheduleDebounce, _apply);
  }

  static Future<void> _apply() async {
    if (_applying) {
      _dirty = true;
      return;
    }
    _applying = true;
    try {
      do {
        _dirty = false;
        await _applyOnce();
      } while (_dirty);
    } catch (e) {
      // 通知失败不影响应用正常使用（但记录日志便于排查）
      debugPrint('[打卡提醒] 排定失败: $e');
    } finally {
      _applying = false;
    }
  }

  static Future<void> _applyOnce() async {
    final settings = _settings;
    if (settings == null || !settings.loaded) return;
    await init();

    final slots = buildReminderSlots(settings.jobs);
    final prompt = _promptPermission;
    _promptPermission = false;
    if (prompt) await ensurePermission();

    final signature = reminderSignature(settings.jobs);
    if (signature == _appliedSignature) {
      _syncTimer();
      return;
    }

    if (slots.isEmpty) {
      // 全部关闭：撤掉本功能排定/展示的通知，其它通知不受影响。
      await _cancelOurNotifications();
      _appliedSignature = signature;
      _syncTimer();
      return;
    }

    // 权限未开启也继续排定：用户之后在系统设置里授权时，已排定的闹钟仍有效。
    // 首次发现已开启提醒但尚未申请过权限（如从旧版本升级）时补问一次，
    // 之后由「通知」页的状态提示引导，不再自动弹窗打扰。
    if (!await notificationsEnabled()) {
      if (!await _permissionAsked()) await requestPermission();
      if (!await notificationsEnabled()) _logPermissionWarning();
    }

    final mode = await _scheduleMode();
    final now = DateTime.now();
    final keepIds = {for (final slot in slots) slot.notificationId};
    // 只取消「本功能排定但已不在新配置里」的通知（改时间、删工作等）。
    await _cancelOurNotifications(keepIds: keepIds);

    var failed = 0;
    for (final slot in slots) {
      try {
        await _plugin.zonedSchedule(
          id: slot.notificationId,
          title: reminderTitle(slot),
          body: reminderBody(slot),
          scheduledDate: _tzTime(nextOccurrenceFor(slot.minute, now)),
          notificationDetails: _details(reminderBody(slot)),
          androidScheduleMode: mode,
          // 每日同一时刻自动重复（含应用被杀/设备重启后由系统触发）
          matchDateTimeComponents: DateTimeComponents.time,
          payload: reminderPayload(slot),
        );
      } catch (e) {
        failed++;
        debugPrint(
          '[打卡提醒] 排定失败（${slot.jobName} '
          '${formatReminderMinute(slot.minute)}）: $e',
        );
      }
    }
    // 有失败时保留空签名，下次设置变化或启动时重试。
    if (failed == 0) _appliedSignature = signature;
    debugPrint(
      '[打卡提醒] 系统级每日通知，已排定 ${slots.length - failed} 条'
      '（${mode.name}）',
    );
    _syncTimer();
    await _check();
  }

  /// 精确闹钟可用时用 exactAllowWhileIdle（到点即发），
  /// 否则回退 inexactAllowWhileIdle（无需特殊权限，可能延迟数分钟）。
  static Future<AndroidScheduleMode> _scheduleMode() async {
    if (await canScheduleExact()) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// 本地时刻 → 调度用 TZDateTime。
  ///
  /// 以 epoch 毫秒构造（时区固定 UTC）可保证「绝对时刻」正确；每日重复
  /// 按该时刻的时钟分量推进，因此在无夏令时的时区（如中国）始终准点。
  static tz.TZDateTime _tzTime(DateTime local) =>
      tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC,
        local.millisecondsSinceEpoch,
      );

  // ---------- 应用内补发 ----------

  /// 启动/停止应用内补发定时器；没有开启提醒的工作时不保留定时器。
  static void _syncTimer() {
    final settings = _settings;
    final hasReminders =
        settings != null &&
        settings.loaded &&
        buildReminderSlots(settings.jobs).isNotEmpty;
    if (!hasReminders) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(_checkInterval, (_) => _check());
  }

  /// 检查补发窗口内到点但未发出的提醒并补发。
  /// 与系统闹钟通道通过「通知栏同 id 已存在」+「当日已发记录」去重。
  static Future<void> _check() async {
    final settings = _settings;
    if (settings == null || !settings.loaded) return;
    if (_checking) return;
    _checking = true;
    try {
      await init();
      final now = DateTime.now();
      final today = dayKeyOf(now);

      // 跨天：清空非今日的已发记录
      if (_fired.any((key) => !key.startsWith('$today|'))) {
        _fired.removeWhere((key) => !key.startsWith('$today|'));
        await _persistFired();
      }

      // 先筛出「到点且未发」的提醒；没有时直接返回，避免频繁查询通知栏。
      final due = [
        for (final slot in buildReminderSlots(settings.jobs))
          if (!_fired.contains(reminderFireKey(today, slot)) &&
              isWithinCatchUpWindow(slot.minute, now))
            slot,
      ];
      if (due.isEmpty) return;

      if (!await notificationsEnabled()) {
        _logPermissionWarning();
        return;
      }

      Set<int>? activeIds;
      try {
        final active = await _plugin.getActiveNotifications();
        activeIds = {
          for (final notification in active)
            if (notification.id != null && _isOurActive(notification))
              notification.id!,
        };
      } catch (e) {
        // 查询失败不影响补发（极端情况下可能重复，可接受）
        debugPrint('[打卡提醒] 查询通知栏失败: $e');
        activeIds = null;
      }

      var changed = false;
      for (final slot in due) {
        final key = reminderFireKey(today, slot);
        // 系统闹钟通道已发出（仍在通知栏）→ 记录已发，跳过
        if (activeIds?.contains(slot.notificationId) ?? false) {
          _fired.add(key);
          changed = true;
          continue;
        }
        try {
          await _plugin.show(
            id: slot.notificationId,
            title: reminderTitle(slot),
            body: reminderBody(slot),
            notificationDetails: _details(reminderBody(slot)),
            payload: reminderPayload(slot),
          );
          _fired.add(key);
          changed = true;
          debugPrint(
            '[打卡提醒] 已补发: ${slot.jobName} '
            '${formatReminderMinute(slot.minute)}',
          );
        } catch (e) {
          debugPrint('[打卡提醒] 补发失败: $e');
        }
      }
      if (changed) await _persistFired();
    } finally {
      _checking = false;
    }
  }

  static void _onResume() {
    // 被系统冻结后回到前台：立即补发窗口内错过的提醒。
    _check();
    // 有些系统会清掉后台闹钟：回到前台时自检，发现缺失就重新排定。
    _verifyPending();
  }

  /// 校验系统里确实存在本功能的排定；缺失时强制重排（自愈）。
  static Future<void> _verifyPending() async {
    final settings = _settings;
    if (settings == null || !settings.loaded) return;
    final slots = buildReminderSlots(settings.jobs);
    if (slots.isEmpty) return;
    final pending = await pendingReminderCount();
    if (pending >= slots.length) return;
    debugPrint('[打卡提醒] 系统排定丢失（$pending/${slots.length}），重新排定');
    _appliedSignature = null;
    await _apply();
  }

  // ---------- 通知清理与识别 ----------

  /// 取消本功能排定/展示、且不在 [keepIds] 中的通知。
  static Future<void> _cancelOurNotifications({
    Set<int> keepIds = const {},
  }) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (!isReminderPayload(request.payload)) continue;
        if (keepIds.contains(request.id)) continue;
        await _plugin.cancel(id: request.id);
      }
    } catch (e) {
      debugPrint('[打卡提醒] 取消过期排定失败: $e');
    }
    try {
      final active = await _plugin.getActiveNotifications();
      for (final notification in active) {
        final id = notification.id;
        if (id == null || keepIds.contains(id)) continue;
        if (!_isOurActive(notification)) continue;
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      debugPrint('[打卡提醒] 取消过期通知失败: $e');
    }
  }

  /// 清除旧版本（无载荷）排定的通知。
  static Future<void> _cancelLegacyPending() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (isReminderPayload(request.payload)) continue;
        await _plugin.cancel(id: request.id);
      }
    } catch (e) {
      debugPrint('[打卡提醒] 清理旧版排定失败: $e');
    }
  }

  /// 清掉旧渠道残留在通知栏中的提醒（渠道已删除，其设置不再生效）。
  static Future<void> _cancelLegacyChannelActive() async {
    try {
      final active = await _plugin.getActiveNotifications();
      for (final notification in active) {
        final id = notification.id;
        if (id == null) continue;
        if (!_legacyChannelIds.contains(notification.channelId)) continue;
        await _plugin.cancel(id: id);
      }
    } catch (e) {
      debugPrint('[打卡提醒] 清理旧渠道通知失败: $e');
    }
  }

  static bool _isOurActive(ActiveNotification notification) =>
      notification.channelId == _channelId ||
      isReminderPayload(notification.payload);

  // ---------- 已发记录持久化 ----------

  static Future<void> _loadFired() async {
    if (_firedLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_firedPrefsKey) ?? const <String>[];
      final today = dayKeyOf(DateTime.now());
      final kept = raw.where((key) => key.startsWith('$today|')).toList();
      _fired
        ..clear()
        ..addAll(kept);
      _firedLoaded = true;
      if (kept.length != raw.length) {
        await prefs.setStringList(_firedPrefsKey, kept);
      }
    } catch (e) {
      _firedLoaded = true;
      debugPrint('[打卡提醒] 读取已发记录失败: $e');
    }
  }

  static Future<void> _persistFired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_firedPrefsKey, _fired.toList());
    } catch (e) {
      debugPrint('[打卡提醒] 保存已发记录失败: $e');
    }
  }

  /// 是否已经主动申请过通知权限（避免每次启动重复弹窗）。
  static Future<bool> _permissionAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_permissionAskedKey) ?? false;
    } catch (_) {
      // 读失败时不再主动弹窗，由「通知」页的状态提示引导
      return true;
    }
  }

  static Future<void> _markPermissionAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionAskedKey, true);
    } catch (e) {
      debugPrint('[打卡提醒] 保存权限提示状态失败: $e');
    }
  }

  // ---------- 其它 ----------

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static NotificationDetails _details(String body) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      icon: _icon,
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: _notificationTitle,
      ),
      actions: const [
        AndroidNotificationAction(
          'open_today',
          '去打卡',
          showsUserInterface: true,
        ),
      ],
    ),
  );

  static void _handleNotificationResponse(NotificationResponse response) {
    if (!isReminderPayload(response.payload)) return;
    onReminderTapped?.call();
  }

  /// 权限未开启的日志限流（补发检查每 30 秒一次，避免刷屏）。
  static void _logPermissionWarning() {
    final now = DateTime.now();
    final last = _lastPermissionWarning;
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _lastPermissionWarning = now;
    debugPrint('[打卡提醒] 通知权限未开启，提醒不会显示');
  }
}

/// 通知渠道诊断结果。
class ReminderChannelStatus {
  const ReminderChannelStatus({
    required this.exists,
    required this.headsUp,
    required this.label,
  });

  /// 渠道是否已创建。
  final bool exists;

  /// 渠道重要性是否足以显示横幅（悬浮）通知。
  final bool headsUp;

  /// 供界面展示的中文说明。
  final String label;
}

/// 应用回到前台时立即补发（被 ROM 冻结期间的定时器不保证运行）。
class _ReminderLifecycleObserver extends WidgetsBindingObserver {
  _ReminderLifecycleObserver();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PunchReminders._onResume();
    }
  }
}
