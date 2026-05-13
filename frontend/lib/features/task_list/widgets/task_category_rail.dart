import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/task.dart';

/// 任务列表页左侧窄侧边栏：在「全部 / block / ddl / todo」之间切换。
class TaskCategoryRail extends StatelessWidget {
  const TaskCategoryRail({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// `null` 表示「全部」。
  final TaskType? selected;
  final ValueChanged<TaskType?> onSelected;

  static const _items = <_RailEntry>[
    _RailEntry(value: null, label: '全部', icon: Icons.dashboard_outlined),
    _RailEntry(value: TaskType.block, label: 'block', icon: Icons.schedule_outlined),
    _RailEntry(value: TaskType.ddl, label: 'ddl', icon: Icons.alarm_outlined),
    _RailEntry(value: TaskType.todo, label: 'todo', icon: Icons.check_circle_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainer,
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in _items)
              _RailButton(
                entry: item,
                selected: item.value == selected,
                onTap: () => onSelected(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailEntry {
  const _RailEntry({required this.value, required this.label, required this.icon});
  final TaskType? value;
  final String label;
  final IconData icon;
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _RailEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    final bg = selected
        ? AppColors.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: selected ? AppColors.primary : Colors.transparent,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                entry.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
