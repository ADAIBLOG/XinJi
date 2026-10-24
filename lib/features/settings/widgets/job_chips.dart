import 'package:flutter/material.dart';
import 'package:xinji/features/settings/data/job.dart';

/// 横向单选工作 chips（带工作标识色）。
/// - showAll = true 时首项为「全部」（selectedJobId 为 null 表示选中全部）
/// - 工作项：色点 + 名称；选中时以工作标识色填充
class JobChips extends StatelessWidget {
  const JobChips({
    super.key,
    required this.jobs,
    required this.selectedJobId,
    required this.onSelect,
    this.showAll = false,
  });

  final List<Job> jobs;
  final String? selectedJobId;
  final ValueChanged<String?> onSelect;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget allChip() {
      final selected = selectedJobId == null;
      return _Chip(
        background: selected ? cs.primary : cs.surfaceContainer,
        foreground: selected ? cs.onPrimary : cs.onSurface,
        label: '全部',
        selected: selected,
        onTap: () => onSelect(null),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (showAll) allChip(),
          for (final job in jobs)
            _JobChip(
              job: job,
              selected: job.id == selectedJobId,
              onTap: () => onSelect(job.id),
            ),
        ],
      ),
    );
  }
}

class _JobChip extends StatelessWidget {
  const _JobChip({
    required this.job,
    required this.selected,
    required this.onTap,
  });

  final Job job;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Chip(
      background: selected ? job.color : cs.surfaceContainer,
      foreground: selected ? Colors.white : cs.onSurface,
      label: job.name,
      selected: selected,
      // 未选中显示工作色点，选中显示白点
      dot: selected ? Colors.white : job.color,
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.background,
    required this.foreground,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  final Color background;
  final Color foreground;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: foreground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
