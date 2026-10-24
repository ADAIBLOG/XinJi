/// 将小时数格式化为「X小时Y分」，如 3.5 → '3小时30分'、0.5 → '30分钟'。
String formatHours(double hours) {
  final totalMinutes = (hours * 60).round();
  if (totalMinutes <= 0) return '0分钟';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '$m分钟';
  if (m == 0) return '$h小时';
  return '$h小时$m分';
}

/// 金额数字：固定保留小数点两位（如 240.00 / 187.50 / 123.46）。
String formatMoney(double v) => v.toStringAsFixed(2);

/// 数量（工时/天数）：最多两位小数并去掉尾零（如 8 / 7.5 / 7.25）。
String formatQuantity(double v) {
  final s = v.toStringAsFixed(2);
  if (s.endsWith('.00')) return s.substring(0, s.length - 3);
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
}
