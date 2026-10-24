import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xinji/app/xinji_app.dart';
import 'package:xinji/core/notifications/punch_reminders.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final settings = SettingsController();
  final records = RecordsController();
  // 跨天分割偏好（每工作独立）：设置 → 打卡统计口径同步（含首次加载完成后的同步）。
  void syncJobSplits() {
    if (!settings.loaded) return;
    records.setJobSplits({
      for (final job in settings.jobs) job.id: job.splitOvernight,
    });
  }

  syncJobSplits();
  settings.addListener(syncJobSplits);
  // 打卡提醒：设置加载完成 / 开关或工作时间变化后重排每日提醒。
  void syncReminders() {
    if (settings.loaded) PunchReminders.reschedule(settings);
  }

  settings.addListener(syncReminders);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: records),
      ],
      child: const XinjiApp(),
    ),
  );
}
