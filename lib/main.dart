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
  // 打卡提醒：设置加载完成 / 开关或提醒时间变化后重排每日提醒。
  // 内部会比对提醒配置签名并去抖，切换主题等无关设置不会触发平台调用。
  void syncReminders() {
    if (settings.loaded) PunchReminders.reschedule(settings);
  }

  settings.addListener(syncReminders);
  // 忘打卡补记的工作日：日薪/月薪没有实际打卡工时，按标准工时回填，
  // 让日历/当日明细显示的工时与正常打卡一致（如 09:00–21:00 → 12h）。
  void syncWorkMarkHours() {
    if (!settings.loaded || !records.loaded) return;
    records.backfillWorkMarkHours({
      for (final job in settings.jobs)
        if (job.calcMode != CalcMode.hourly) job.id: job.shiftMinutes,
    });
  }

  syncWorkMarkHours();
  settings.addListener(syncWorkMarkHours);
  records.addListener(syncWorkMarkHours);
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
