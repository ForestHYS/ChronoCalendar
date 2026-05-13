import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/tag.dart';
import '../../../domain/models/task.dart';
import '../../../domain/models/task_status.dart';
import '../../home/widgets/title_with_tags_row.dart';

/// 任务列表中的单行卡片：标题 + 标签 + 类型/状态徽标 + 类型相关副标题。
class TaskRowCard extends StatelessWidget {
  const TaskRowCard({
    super.key,
    required this.task,
    required this.tags,
    required this.onTap,
  });

  final Task task;
  final List<Tag> tags;
  final VoidCallback onTap;

  String _subtitle() {
    switch (task.type) {
      case TaskType.block:
        if (task.startAt == null || task.endAt == null) return 'block';
        final s = DateFormat('M/d HH:mm').format(task.startAt!);
        final e = DateFormat('HH:mm').format(task.endAt!);
        return '$s – $e';
      case TaskType.ddl:
        if (task.dueAt == null) return 'ddl';
        return '截止 ${DateFormat('M/d HH:mm').format(task.dueAt!)}';
      case TaskType.todo:
        final parts = <String>[];
        if (task.dueAt != null) {
          parts.add('截止 ${DateFormat('M/d HH:mm').format(task.dueAt!)}');
        }
        if (task.focusTotalSeconds > 0) {
          parts.add('已专注 ${_formatHm(task.focusTotalSeconds)}');
        }
        if (task.expectedMinutes != null) {
          parts.add('预计 ${task.expectedMinutes}分钟');
        }
        if (task.subtasks.isNotEmpty) {
          final done = task.subtasks.where((s) => s.done).length;
          parts.add('$done/${task.subtasks.length} 子任务');
        }
        return parts.isEmpty ? 'todo' : parts.join(' · ');
    }
  }

  static String _formatHm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h >= 1 && m > 0) return '${h}h${m}m';
    if (h >= 1) return '${h}h';
    return '${m}m';
  }

  static TaskStatus? _badgeStatus(Task t) {
    if (t.isOverdue) return TaskStatus.overdue;
    if (t.status == TaskStatus.completed) return TaskStatus.completed;
    if (t.status == TaskStatus.cancelled) return TaskStatus.cancelled;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badgeStatus(task);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TitleWithTagsRow(
                title: task.title,
                tags: tags,
                titleStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TypeBadge(type: task.type),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    _StatusBadge(status: badge),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final TaskType type;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        type.name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: palette.$2,
        ),
      ),
    );
  }

  static (Color, Color) _palette(TaskType t) {
    switch (t) {
      case TaskType.block:
        return (const Color(0xFFE0F2FE), const Color(0xFF0369A1));
      case TaskType.ddl:
        return (const Color(0xFFFFE4E6), const Color(0xFFBE123C));
      case TaskType.todo:
        return (const Color(0xFFDCFCE7), const Color(0xFF15803D));
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: palette.$2,
        ),
      ),
    );
  }

  static String _label(TaskStatus s) {
    switch (s) {
      case TaskStatus.overdue:
        return '超时';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.cancelled:
        return '已取消';
      case TaskStatus.active:
        return '进行中';
    }
  }

  static (Color, Color) _palette(TaskStatus s) {
    switch (s) {
      case TaskStatus.overdue:
        return (const Color(0xFFFEE2E2), AppColors.error);
      case TaskStatus.completed:
        return (const Color(0xFFDCFCE7), AppColors.success);
      case TaskStatus.cancelled:
        return (AppColors.surfaceContainerHigh, AppColors.onSurfaceVariant);
      case TaskStatus.active:
        return (AppColors.primaryContainer, AppColors.primary);
    }
  }
}
