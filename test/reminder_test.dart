import 'package:flutter_test/flutter_test.dart';
import 'package:xinji/core/notifications/reminder_schedule.dart';
import 'package:xinji/features/settings/data/job.dart';

void main() {
  Job job({
    String id = 'j1',
    String name = '工作',
    bool reminders = true,
    List<int>? minutes,
    int workStart = 540,
    int workEnd = 1080,
  }) => Job(
    id: id,
    name: name,
    punchReminders: reminders,
    reminderMinutes: minutes ?? const [540, 1080],
    workStart: workStart,
    workEnd: workEnd,
  );

  group('buildReminderSlots', () {
    test('只为开启提醒的工作生成，按时间排序且通知 id 不冲突', () {
      final slots = buildReminderSlots([
        job(id: 'a', name: '工作 A', minutes: [1080, 540]),
        job(id: 'b', name: '工作 B', reminders: false),
        job(id: 'c', name: '工作 C', minutes: [600, 540, 600]),
      ]);
      expect(slots.map((s) => '${s.jobId}:${s.minute}').toList(), [
        'a:540',
        'a:1080',
        'c:540',
        'c:600',
      ]);
      // id = 工作序号 × 100000 + 分钟；关闭提醒的工作仍占列表序号
      expect(slots.map((s) => s.notificationId).toList(), [
        540,
        1080,
        200540,
        200600,
      ]);
      expect(slots.map((s) => s.notificationId).toSet().length, slots.length);
    });

    test('过滤非法分钟并去重', () {
      final slots = buildReminderSlots([
        job(minutes: [-1, 0, 1439, 1440, 600, 600]),
      ]);
      expect(slots.map((s) => s.minute).toList(), [0, 600, 1439]);
    });

    test('未开启提醒的工作不产生任何提醒', () {
      expect(buildReminderSlots([job(reminders: false)]), isEmpty);
    });
  });

  group('isWithinCatchUpWindow', () {
    final now = DateTime(2026, 10, 27, 9, 5);
    test('到点后的补发窗口内返回 true', () {
      expect(isWithinCatchUpWindow(540, now), true); // 5 分钟前
      expect(isWithinCatchUpWindow(545, now), true); // 刚好到点
    });

    test('未到点、超出窗口或已跨天返回 false', () {
      expect(isWithinCatchUpWindow(550, now), false);
      expect(isWithinCatchUpWindow(520, now), false); // 25 分钟前
      expect(isWithinCatchUpWindow(540, DateTime(2026, 10, 27, 0, 5)), false);
    });

    test('支持自定义窗口', () {
      expect(
        isWithinCatchUpWindow(
          540,
          DateTime(2026, 10, 27, 9, 30),
          window: const Duration(minutes: 60),
        ),
        true,
      );
      expect(
        isWithinCatchUpWindow(
          540,
          DateTime(2026, 10, 27, 9, 30),
          window: const Duration(minutes: 10),
        ),
        false,
      );
    });
  });

  group('nextOccurrenceFor', () {
    test('今天未到点 → 今天', () {
      final next = nextOccurrenceFor(600, DateTime(2026, 10, 27, 9));
      expect(next, DateTime(2026, 10, 27, 10));
    });

    test('今天已过点 → 明天', () {
      final next = nextOccurrenceFor(540, DateTime(2026, 10, 27, 9));
      expect(next, DateTime(2026, 10, 28, 9));
    });

    test('跨月/跨年正确进位', () {
      expect(
        nextOccurrenceFor(60, DateTime(2026, 10, 31, 23, 59)),
        DateTime(2026, 11, 1, 1),
      );
      expect(
        nextOccurrenceFor(30, DateTime(2026, 12, 31, 23, 59)),
        DateTime(2027, 1, 1, 0, 30),
      );
    });

    test('nextReminderDateTime 取最近一条，未开启提醒时为 null', () {
      final jobs = [
        job(id: 'a', minutes: [1080, 540]),
        job(id: 'b', reminders: false, minutes: [600]),
      ];
      expect(
        nextReminderDateTime(jobs, DateTime(2026, 10, 27, 10)),
        DateTime(2026, 10, 27, 18),
      );
      expect(
        nextReminderDateTime(jobs, DateTime(2026, 10, 27, 19)),
        DateTime(2026, 10, 28, 9),
      );
      expect(
        nextReminderDateTime([job(reminders: false)], DateTime.now()),
        null,
      );
    });
  });

  group('提醒文案', () {
    test('上下班时间点使用专属文案，其它时间点用通用文案', () {
      final slots = buildReminderSlots([
        job(minutes: [540, 780, 1080]),
      ]);
      expect(reminderBody(slots[0]), '「工作」09:00 上班时间到，记得打卡。');
      expect(reminderBody(slots[1]), '「工作」13:00，记得打卡。');
      expect(reminderBody(slots[2]), '「工作」18:00 下班时间到，记得打卡下班。');
      expect(reminderTitle(slots[0]), '打卡提醒');
    });

    test('上下班时间相同时只提示上班', () {
      final slot = buildReminderSlots([
        job(minutes: [540], workStart: 540, workEnd: 540),
      ]).single;
      expect(slot.isWorkStart, true);
      expect(slot.isWorkEnd, false);
      expect(reminderBody(slot), contains('上班'));
    });
  });

  group('载荷与去重键', () {
    test('载荷带前缀与工作/时间，可用于筛选本应用通知', () {
      final slot = buildReminderSlots([
        job(id: 'job-1', minutes: [540]),
      ]).single;
      expect(reminderPayload(slot), 'xinji.reminder|job-1|540');
      expect(isReminderPayload(reminderPayload(slot)), true);
      expect(isReminderPayload('other|job-1|540'), false);
      expect(isReminderPayload(null), false);
      expect(reminderFireKey('2026-10-27', slot), '2026-10-27|job-1|540');
    });
  });

  group('reminderSignature', () {
    test('只有提醒相关配置变化才改变签名', () {
      expect(reminderSignature([job()]), reminderSignature([job()]));
      expect(
        reminderSignature([job()]),
        isNot(reminderSignature([job(reminders: false)])),
      );
      expect(
        reminderSignature([job()]),
        isNot(reminderSignature([job(name: '改名')])),
      );
      // 时间点顺序不同但集合相同 → 同一签名（无需重排）
      expect(
        reminderSignature([
          job(minutes: [1080, 540]),
        ]),
        reminderSignature([
          job(minutes: [540, 1080]),
        ]),
      );
      // 上下班时间影响提醒文案（上班/下班提示），必须计入签名
      expect(
        reminderSignature([job(workStart: 540)]),
        isNot(reminderSignature([job(workStart: 600)])),
      );
      expect(
        reminderSignature([job(workEnd: 1080)]),
        isNot(reminderSignature([job(workEnd: 1140)])),
      );
    });
  });

  group('Job.fromJson 提醒时间规整', () {
    test('过滤越界值、去重并排序', () {
      final parsed = Job.fromJson({
        'id': 'j',
        'name': '脏数据',
        'punchReminders': true,
        'reminderMinutes': [1080, -5, 540, 1440, 540, 780],
      });
      expect(parsed.reminderMinutes, [540, 780, 1080]);
    });
  });
}
