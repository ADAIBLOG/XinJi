import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette._();

  static const brand = Color(0xFF7C3AED);
  static const brandDark = Color(0xFF5B21B6);
  static const brandSoft = Color(0xFFA78BFA);

  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);

  static const darkBackground = Color(0xFF0D0D0D);
  static const darkSurface = Color(0xFF141414);
  static const darkCard = Color(0xFF1A1A1A);
  static const darkElevated = Color(0xFF232326);
  static const darkBorder = Color(0xFF2C2C2E);

  static const List<Color> accentColors = [
    Color(0xFF7C3AED),
    Color(0xFF5856D6),
    Color(0xFF0A84FF),
    Color(0xFF007AFF),
    Color(0xFF00BCD4),
    Color(0xFF1ABC9C),
    Color(0xFF30D158),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFFF6D00),
    Color(0xFFFF375F),
    Color(0xFFFF2D92),
  ];

  /// 休息日标记色（日历中未打卡的日子），默认清新绿。
  static const defaultRestColor = Color(0xFF22C55E);

  static const List<Color> restColors = [
    Color(0xFF22C55E), // 清新绿
    Color(0xFF30D158), // 薄荷绿
    Color(0xFF34C759), // 草地绿
    Color(0xFF10B981), // 祖母绿
    Color(0xFF0D9488), // 青碧
    Color(0xFF84CC16), // 青柠
    Color(0xFF0A84FF), // 晴空蓝
    Color(0xFF9CA3AF), // 石墨灰
  ];

  /// 请假日标记色，默认琥珀黄。
  static const defaultLeaveColor = Color(0xFFFBBF24);

  static const List<Color> leaveColors = [
    Color(0xFFFBBF24), // 琥珀黄
    Color(0xFFFACC15), // 明黄
    Color(0xFFFDE047), // 柠檬黄
    Color(0xFFEAB308), // 芥末黄
    Color(0xFFF59E0B), // 琥珀橙
    Color(0xFFFB923C), // 橙黄
    Color(0xFFF0ABFC), // 淡紫
    Color(0xFFD4D4D8), // 暖灰
  ];

  /// 缺勤（未打卡且非排班休息）背景色。
  static const absentColor = Color(0xFFEF4444);

  /// 加班日标记色（当日有加班时使用比正常上班更深的底色）。
  static const List<Color> overtimeColors = [
    Color(0xFF6D28D9), // 深紫
    Color(0xFF4F46E5), // 靛蓝
    Color(0xFF1E40AF), // 藏青
    Color(0xFF0F766E), // 深碧
    Color(0xFFB45309), // 深琥珀
    Color(0xFFC2410C), // 深橙
    Color(0xFFBE123C), // 深玫红
    Color(0xFF3F6212), // 橄榄
  ];

  /// 工作标识色（多工作时区分各工作：chips、今日合计、图表堆叠、明细弹层）。
  static const List<Color> jobColors = [
    Color(0xFF7C3AED), // 紫（品牌）
    Color(0xFF0A84FF), // 蓝
    Color(0xFFFF375F), // 玫红
    Color(0xFF1ABC9C), // 青碧
    Color(0xFFFF9500), // 橙
    Color(0xFF5856D6), // 靛
    Color(0xFF00BCD4), // 天青
    Color(0xFFFF2D92), // 桃红
  ];
}
