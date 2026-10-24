import 'package:xinji/core/utils/day_key.dart';

/// 一次打卡：上班（isIn = true）或下班（isIn = false）。
class PunchRecord {
  const PunchRecord({
    required this.id,
    required this.dateKey,
    required this.time,
    required this.isIn,
    this.jobId = '',
  });

  final String id;
  final String dateKey;
  final DateTime time;
  final bool isIn;

  /// 归属工作 id（旧数据为空，读取时迁移为默认工作）。
  final String jobId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'dateKey': dateKey,
    'time': time.millisecondsSinceEpoch,
    'isIn': isIn,
    'jobId': jobId,
  };

  static PunchRecord fromJson(Map<String, dynamic> json) => PunchRecord(
    id: json['id'] as String,
    dateKey: json['dateKey'] as String,
    time: DateTime.fromMillisecondsSinceEpoch((json['time'] as num).toInt()),
    isIn: json['isIn'] as bool? ?? true,
    jobId: json['jobId'] as String? ?? '',
  );

  static String todayKey() => dayKeyOf(DateTime.now());
}

/// 一段完整的上班时段（下班打卡后闭合）。
class WorkSession {
  const WorkSession({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}
