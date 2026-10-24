/// yyyy-MM-dd 形式的日期键。
String dayKeyOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime dateOfKey(String key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime weekStartOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  // 周一为一周开始
  final offset = (d.weekday - 1) % 7;
  return d.subtract(Duration(days: offset));
}

/// 距离下一个午夜的时长（供跨日自动刷新定时器使用）。
Duration untilNextMidnight(DateTime now) {
  final next = DateTime(now.year, now.month, now.day + 1);
  return next.difference(now);
}
