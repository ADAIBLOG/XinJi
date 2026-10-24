import 'package:flutter_test/flutter_test.dart';
import 'package:xinji/features/statistics/pages/stats_page.dart';

void main() {
  test('周期锚点：每周循环起始日', () {
    // 2026-10-24 是周六
    final now = DateTime(2026, 10, 24, 15);
    // 周一起点 → 10-19
    expect(weekAnchorStartOf(now, 1), DateTime(2026, 10, 19));
    // 周日起点 → 10-18
    expect(weekAnchorStartOf(now, 7), DateTime(2026, 10, 18));
    // 周六起点 → 当天
    expect(weekAnchorStartOf(now, 6), DateTime(2026, 10, 24));
  });

  test('周期锚点：每月循环起始日（短月按月末）', () {
    expect(
      monthAnchorStartOf(DateTime(2026, 10, 24), 1),
      DateTime(2026, 10, 1),
    );
    expect(
      monthAnchorStartOf(DateTime(2026, 10, 24), 15),
      DateTime(2026, 10, 15),
    );
    // 锚点 15 号，当月 5 号 → 上一周期起点为上月 15 号
    expect(
      monthAnchorStartOf(DateTime(2026, 10, 5), 15),
      DateTime(2026, 9, 15),
    );
    // 短月：2 月的 31 号锚点 → 按 1 月 31 日计
    expect(
      monthAnchorStartOf(DateTime(2027, 2, 10), 31),
      DateTime(2027, 1, 31),
    );
    // 1 月 5 号 + 31 号锚点 → 去年 12 月 31 日
    expect(
      monthAnchorStartOf(DateTime(2026, 1, 5), 31),
      DateTime(2025, 12, 31),
    );
  });

  test('周期锚点：年度循环起始', () {
    expect(
      yearAnchorStartOf(DateTime(2026, 10, 24), 1, 1),
      DateTime(2026, 1, 1),
    );
    expect(
      yearAnchorStartOf(DateTime(2026, 10, 24), 3, 1),
      DateTime(2026, 3, 1),
    );
    // 年度锚点 3 月 1 日，2 月 10 日 → 上一周期为去年 3 月 1 日
    expect(
      yearAnchorStartOf(DateTime(2026, 2, 10), 3, 1),
      DateTime(2025, 3, 1),
    );
  });
}
