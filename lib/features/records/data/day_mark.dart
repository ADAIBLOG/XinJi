/// 手工日期标记类型。
enum DayMarkType { work, rest, leave }

/// 手工日期标记：忘打卡补记工作日（可带工时）、休息日或请假。
class DayMark {
  const DayMark.work(this.hours) : type = DayMarkType.work;

  const DayMark.rest() : type = DayMarkType.rest, hours = 0;

  const DayMark.leave() : type = DayMarkType.leave, hours = 0;

  final DayMarkType type;

  /// 工作日标记的工时（小时），仅时薪模式参与计薪。
  final double hours;

  bool get isWork => type == DayMarkType.work;
  bool get isRest => type == DayMarkType.rest;
  bool get isLeave => type == DayMarkType.leave;

  Map<String, dynamic> toJson() => {'type': type.index, 'hours': hours};

  static DayMark fromJson(Map<String, dynamic> json) {
    final hours = (json['hours'] as num?)?.toDouble() ?? 0;
    final typeIndex = json['type'] as int?;
    if (typeIndex != null &&
        typeIndex >= 0 &&
        typeIndex < DayMarkType.values.length) {
      switch (DayMarkType.values[typeIndex]) {
        case DayMarkType.work:
          return DayMark.work(hours);
        case DayMarkType.rest:
          return const DayMark.rest();
        case DayMarkType.leave:
          return const DayMark.leave();
      }
    }
    // 兼容旧格式（isWork 布尔）
    return json['isWork'] == true ? DayMark.work(hours) : const DayMark.rest();
  }
}
