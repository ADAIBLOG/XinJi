import 'package:xinji/features/settings/data/job.dart';

/// 打卡提醒的纯逻辑（不依赖通知插件，便于单元测试）：
/// 时间点规整、通知 id / 载荷 / 去重键、正文文案、补发窗口与下次触发时刻。

/// 通知载荷前缀：用于识别「本应用排定的打卡提醒」，避免误取消其它通知。
const reminderPayloadPrefix = 'xinji.reminder';

/// 提醒「补发」窗口：系统闹钟被 ROM 拦截/延迟、或应用被冻结后重新回到前台时，
/// 应用内只补发最近这段时间内到点的提醒。更早的错过提醒不再弹出，
/// 避免一次刷出多条过期通知（例如深夜打开应用时弹出早晨的提醒）。
const reminderCatchUpWindow = Duration(minutes: 15);

/// 通知 id 步长：id = 工作序号 × 步长 + 分钟数（分钟 < 1440，故不会碰撞）。
const _notificationIdStride = 100000;

/// 排序、去重并过滤非法时间点（仅保留 0 ≤ minute < 1440）。
List<int> normalizedReminderMinutes(Iterable<int> minutes) {
  final unique = <int>{};
  for (final minute in minutes) {
    if (minute >= 0 && minute < 1440) unique.add(minute);
  }
  return unique.toList()..sort();
}

/// 一条待提醒项：某份工作的某个时间点。
class ReminderSlot {
  const ReminderSlot({
    required this.jobId,
    required this.jobName,
    required this.minute,
    required this.notificationId,
    this.isWorkStart = false,
    this.isWorkEnd = false,
  });

  /// 工作 id（去重键的一部分，跨重启稳定）。
  final String jobId;

  /// 工作名称（通知正文中的「」内容）。
  final String jobName;

  /// 当天分钟数（0 ~ 1439）。
  final int minute;

  /// 系统通知 id（同一提醒每天复用，重复触发时覆盖而不是叠加）。
  final int notificationId;

  /// 该时间点是否正好是上班时间。
  final bool isWorkStart;

  /// 该时间点是否正好是下班时间。
  final bool isWorkEnd;
}

/// 汇总所有开启提醒的工作的时间点（按工作顺序、时间升序）。
List<ReminderSlot> buildReminderSlots(List<Job> jobs) {
  final slots = <ReminderSlot>[];
  for (final (index, job) in jobs.indexed) {
    if (!job.punchReminders) continue;
    for (final minute in normalizedReminderMinutes(job.reminderMinutes)) {
      slots.add(
        ReminderSlot(
          jobId: job.id,
          jobName: job.name,
          minute: minute,
          notificationId: index * _notificationIdStride + minute,
          isWorkStart: minute == job.workStart,
          // 上下班时间相同时只按「上班」文案，避免重复语义
          isWorkEnd: minute == job.workEnd && minute != job.workStart,
        ),
      );
    }
  }
  return slots;
}

/// 分钟数 → HH:mm。
String formatReminderMinute(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:'
    '${(minute % 60).toString().padLeft(2, '0')}';

/// 通知标题。
String reminderTitle(ReminderSlot slot) => '打卡提醒';

/// 通知正文（按是否上下班时间给出更具体的提示）。
String reminderBody(ReminderSlot slot) {
  final time = formatReminderMinute(slot.minute);
  if (slot.isWorkStart) return '「${slot.jobName}」$time 上班时间到，记得打卡。';
  if (slot.isWorkEnd) return '「${slot.jobName}」$time 下班时间到，记得打卡下班。';
  return '「${slot.jobName}」$time，记得打卡。';
}

/// 通知载荷：`xinji.reminder|工作 id|分钟数`。
String reminderPayload(ReminderSlot slot) =>
    '$reminderPayloadPrefix|${slot.jobId}|${slot.minute}';

/// 是否为打卡提醒通知的载荷。
bool isReminderPayload(String? payload) =>
    payload != null && payload.startsWith(reminderPayloadPrefix);

/// 当日去重键：同一天内同一工作同一时间点只发一次。
String reminderFireKey(String dayKey, ReminderSlot slot) =>
    '$dayKey|${slot.jobId}|${slot.minute}';

/// 提醒时间点的下一次触发时刻（今天已过则明天）。
///
/// 只做本地日历换算；转成调度时区由调用方负责。
DateTime nextOccurrenceFor(int minuteOfDay, DateTime now) {
  final minute = minuteOfDay.clamp(0, 1439);
  var next = DateTime(now.year, now.month, now.day, minute ~/ 60, minute % 60);
  if (!next.isAfter(now)) {
    next = DateTime(
      next.year,
      next.month,
      next.day + 1,
      next.hour,
      next.minute,
    );
  }
  return next;
}

/// 所有开启提醒中最近的一次触发时刻（没有提醒时返回 null）。
DateTime? nextReminderDateTime(List<Job> jobs, DateTime now) {
  DateTime? next;
  for (final slot in buildReminderSlots(jobs)) {
    final occurrence = nextOccurrenceFor(slot.minute, now);
    if (next == null || occurrence.isBefore(next)) next = occurrence;
  }
  return next;
}

/// 该时间点是否已到点且仍在补发窗口内。
///
/// 早于当前时刻但超出 [window] 的提醒视为「已错过」，不再补发；
/// 尚未到点的提醒返回 false。
bool isWithinCatchUpWindow(
  int minuteOfDay,
  DateTime now, {
  Duration window = reminderCatchUpWindow,
}) {
  final minute = minuteOfDay.clamp(0, 1439);
  final due = DateTime(now.year, now.month, now.day, minute ~/ 60, minute % 60);
  final late = now.difference(due);
  return !late.isNegative && late <= window;
}

/// 提醒配置签名：只有提醒相关配置变化时才需要重新排定系统通知，
/// 避免切换主题、货币等无关设置也触发一轮平台调用。
///
/// 上下班时间也计入签名：它们决定提醒文案是「上班/下班」还是通用提示。
String reminderSignature(List<Job> jobs) => [
  for (final job in jobs)
    '${job.id}|${job.name}|${job.punchReminders ? 1 : 0}|'
        '${job.workStart}|${job.workEnd}|'
        '${normalizedReminderMinutes(job.reminderMinutes).join(',')}',
].join(';');
