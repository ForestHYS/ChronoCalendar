import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/tag.dart';
import '../../../domain/models/task.dart';
import '../utils/calendar_task_layout.dart';

class CalendarTaskBlock extends StatelessWidget {
  const CalendarTaskBlock({
    super.key,
    required this.task,
    required this.repo,
    this.compact = false,
    this.onTap,
  });

  final Task task;
  final TaskRepository repo;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tags = task.tagIds.map(repo.tagById).whereType<Tag>();
    final tag = tags.isEmpty ? null : tags.first;
    final color = _taskColor(task, tag);
    final bg = color.withValues(alpha: task.type == TaskType.ddl ? 0.12 : 0.15);
    final border = color.withValues(alpha: task.type == TaskType.ddl ? 0.55 : 0.35);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(compact ? 7 : 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 7 : 9),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 7 : 9),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(
                  _subtitle(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _taskColor(Task task, Tag? tag) {
    if (tag != null) return tag.color;
    return switch (task.type) {
      TaskType.block => AppColors.primary,
      TaskType.ddl => AppColors.error,
      TaskType.todo => AppColors.success,
    };
  }

  String _subtitle(Task task) {
    return switch (task.type) {
      TaskType.block when task.startAt != null && task.endAt != null =>
        '${formatHm(task.startAt!)} - ${formatHm(task.endAt!)}',
      TaskType.ddl when task.dueAt != null => '截止 ${formatHm(task.dueAt!)}',
      TaskType.todo when task.dueAt != null => '待办 ${formatHm(task.dueAt!)}',
      _ => task.type.name,
    };
  }
}

class CalendarDeadlinePin extends StatelessWidget {
  const CalendarDeadlinePin({
    super.key,
    required this.task,
    this.compact = false,
    this.onTap,
  });

  final Task task;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final due = task.dueAt;
    final label = due == null ? task.title : '${formatHm(due)} ${task.title}';
    final color = switch (task.type) {
      TaskType.todo => AppColors.success,
      _ => AppColors.error,
    };
    final lineColor = color.withValues(alpha: 0.72);
    final lineInset = compact ? -5.0 : -8.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: compact ? 32 : 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: lineInset,
              right: compact ? -5 : -10,
              top: compact ? 18 : 21,
              child: Container(height: 1.5, color: lineColor),
            ),
            Positioned(
              left: lineInset,
              top: compact ? 16 : 18.5,
              child: Container(
                width: compact ? 5 : 6,
                height: compact ? 5 : 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: compact ? 4 : 10,
              top: 0,
              child: Container(
                constraints: BoxConstraints(maxWidth: compact ? 92 : 180),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 5 : 7,
                  vertical: compact ? 2 : 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 9.5 : 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
