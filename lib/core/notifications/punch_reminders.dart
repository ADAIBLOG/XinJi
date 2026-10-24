import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:xinji/features/settings/state/settings_controller.dart';

/// 打卡提醒（每日定时通知）：每份工作独立开关与自定义时间点列表。
///
/// 实现说明（v1.38.1 起，双通道）：
/// - **系统闹钟**：zonedSchedule + matchDateTimeComponents（每日重复）注册到
///   系统 AlarmManager，应用被杀/重启后仍可到点弹出；开机后由插件的
///   BootReceiver 自动恢复。
/// - **应用内 Timer 补发**：部分 ROM（如 MIUI）对第三方应用的闹钟有
///   拦截/延迟，且错过的通知不会补——因此应用运行期间（前台或后台存活）
///   每 30 秒检查一次，当天已到点但尚未发出的提醒立即补发；被系统
///   冻结后回到前台也会立即补发。通过查询通知栏（同 id 已存在）与
///   当日已发记录去重，与闹钟通道互不重复。
class PunchReminders {
  PunchReminders._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _tzReady = false;

  /// 应用内补发定时器。
  static Timer? _timer;
  static SettingsController? _settings;

  /// 当日已发记录（dayKey|jobId|minute），防重复发送。
  static final Set<String> _fired = {};

  /// 初始化插件（幂等）：时区数据库 + 通知渠道（Importance.max，
  /// 渠道先于任何调度存在）。
  static Future<void> init() async {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notify'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'punch_reminders',
            '打卡提醒',
            description: '上下班时间到点提醒打卡',
            importance: Importance.max,
          ),
        );
    _initialized = true;
  }

  /// 请求通知权限（Android 13+；已授权时为空操作）。
  static Future<bool> requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 按设置重排提醒（双通道）：
  /// 1. 把开启提醒工作的全部时间点注册为系统级每日通知；
  /// 2. 启动应用内补发定时器。
  /// 设置或提醒时间变化后再次调用即可（内部先取消全部已排定项）。
  static Future<void> reschedule(SettingsController settings) async {
    _settings = settings;
    try {
      await init();
      await _plugin.cancelAll();

      var scheduled = 0;
      var permissionGranted = false;
      for (final (i, job) in settings.jobs.indexed) {
        if (!job.punchReminders) continue;
        if (!permissionGranted) {
          permissionGranted = await requestPermission();
          if (!permissionGranted) {
            debugPrint('[打卡提醒] 通知权限未授权，跳过排定');
            _startTimer();
            return;
          }
        }
        for (final minute in job.reminderMinutes) {
          await _plugin.zonedSchedule(
            // 工作序号 × 10万 + 分钟（分钟 < 1440），多工作多时间点不碰撞
            id: i * 100000 + minute,
            title: '打卡提醒',
            body: '「${job.name}」${_timeLabel(minute)}，记得打卡。',
            scheduledDate: _nextOccurrence(minute),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'punch_reminders',
                '打卡提醒',
                channelDescription: '上下班时间到点提醒打卡',
                importance: Importance.max,
                priority: Priority.max,
                playSound: true,
                icon: 'ic_stat_notify',
                styleInformation: BigTextStyleInformation(''),
              ),
            ),
            androidScheduleMode: await _scheduleMode(),
            // 每日同一时刻自动重复（含应用被杀/设备重启后由系统触发）
            matchDateTimeComponents: DateTimeComponents.time,
          );
          scheduled++;
        }
      }
      debugPrint('[打卡提醒] 系统级每日通知，已排定 $scheduled 条');
    } catch (e) {
      // 通知失败不影响应用正常使用（但记录日志便于排查）
      debugPrint('[打卡提醒] 排定失败: $e');
    }
    _startTimer();
  }

  /// 启动应用内补发定时器（30 秒周期；重复启动自动重建）。
  static void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    // 启动/回前台立即检查一次（补发冻结期间错过的提醒）
    _check();
  }

  /// 检查当天已到点但未发出的提醒并补发。
  /// 与系统闹钟通道通过「通知栏同 id 已存在」+「当日已发记录」去重。
  static Future<void> _check() async {
    final settings = _settings;
    if (settings == null || !settings.loaded) return;
    final now = DateTime.now();
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    // 跨天：清空已发记录
    _fired.removeWhere((k) => !k.startsWith('$dayKey|'));
    final minuteOfDay = now.hour * 60 + now.minute;

    // 通知栏现存通知的 id（系统闹钟通道已发出的）
    Set<int>? activeIds;
    try {
      final active = await _plugin.getActiveNotifications();
      activeIds = active.map((n) => n.id).whereType<int>().toSet();
    } catch (_) {
      activeIds = null; // 查询失败不影响补发（可能重复，可接受）
    }

    for (final (i, job) in settings.jobs.indexed) {
      if (!job.punchReminders) continue;
      for (final minute in job.reminderMinutes) {
        // 当天已到点（含刚到的）才补发；未到点跳过
        if (minuteOfDay < minute) continue;
        final id = i * 100000 + minute;
        final key = '$dayKey|${job.id}|$minute';
        if (_fired.contains(key)) continue;
        // 闹钟通道已发出（仍在通知栏）→ 记录已发，跳过
        if (activeIds?.contains(id) ?? false) {
          _fired.add(key);
          continue;
        }
        try {
          await _plugin.show(
            id: id,
            title: '打卡提醒',
            body: '「${job.name}」${_timeLabel(minute)}，记得打卡。',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'punch_reminders',
                '打卡提醒',
                channelDescription: '上下班时间到点提醒打卡',
                importance: Importance.max,
                priority: Priority.max,
                playSound: true,
                icon: 'ic_stat_notify',
                styleInformation: BigTextStyleInformation(''),
              ),
            ),
          );
          debugPrint('[打卡提醒] 已补发: ${job.name} ${_timeLabel(minute)}');
          _fired.add(key);
        } catch (e) {
          debugPrint('[打卡提醒] 补发失败: $e');
        }
      }
    }
  }

  /// 精确闹钟可用时用 exactAllowWhileIdle（到点即发），
  /// 否则回退 inexactAllowWhileIdle（无需特殊权限，可能延迟数分钟）。
  static Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final exact = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.canScheduleExactNotifications();
      if (exact == true) return AndroidScheduleMode.exactAllowWhileIdle;
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// 提醒时间点的下一次触发时刻（今天已过则明天）。
  /// 按 epoch 毫秒换算成 TZDateTime：绝对时刻正确，不受时区库影响。
  static tz.TZDateTime _nextOccurrence(int minuteOfDay) {
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!next.isAfter(now)) {
      next = DateTime(next.year, next.month, next.day + 1, next.hour, next.minute);
    }
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      next.millisecondsSinceEpoch,
    );
  }

  /// 分钟数 → HH:mm。
  static String _timeLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}
