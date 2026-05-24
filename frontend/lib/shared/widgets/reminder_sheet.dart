import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';

/// 半屏提醒弹窗：当 [Task.remindAt] 到点且 app 在前台时弹出。
///
/// 提供快捷操作：开始专注 / 标记完成 / 稍后再提醒（5/30 分钟）/ 查看详情 / 关闭。
class ReminderSheet extends ConsumerWidget {
  const ReminderSheet({super.key, required this.task});

  final Task task;

  /// 以模态方式显示。同一时刻同一任务只展示一次。
  static Future<void> show(BuildContext context, Task task) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.5,
        child: ReminderSheet(task: task),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.notifications_active, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '任务提醒',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _typeLabel(task.type),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                task.title.isEmpty ? '(未命名任务)' : task.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              _DeadlineLine(task: task),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  task.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              _ActionsRow(task: task, sheetContext: context),
              const SizedBox(height: 8),
              _SnoozeRow(task: task, sheetContext: context),
            ],
          ),
        ),
      ),
    );
  }

  static String _typeLabel(TaskType t) {
    switch (t) {
      case TaskType.block:
        return '时间块';
      case TaskType.ddl:
        return '截止任务';
      case TaskType.todo:
        return '待办';
    }
  }
}

class _DeadlineLine extends StatelessWidget {
  const _DeadlineLine({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('MM-dd HH:mm');
    final lines = <String>[];
    switch (task.type) {
      case TaskType.block:
        if (task.startAt != null) lines.add('开始 ${df.format(task.startAt!)}');
        if (task.endAt != null) lines.add('结束 ${df.format(task.endAt!)}');
        break;
      case TaskType.ddl:
        if (task.dueAt != null) lines.add('截止 ${df.format(task.dueAt!)}');
        break;
      case TaskType.todo:
        if (task.dueAt != null) lines.add('截止 ${df.format(task.dueAt!)}');
        if (task.expectedMinutes != null) {
          lines.add('预计 ${task.expectedMinutes} 分钟');
        }
        break;
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.event, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            lines.join('   ·   '),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({required this.task, required this.sheetContext});
  final Task task;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final canComplete = task.status == TaskStatus.active ||
        task.status == TaskStatus.overdue;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('开始专注'),
            onPressed: () {
              Navigator.of(sheetContext).maybePop();
              context.push('/pomodoro/${task.id}');
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('标记完成'),
            onPressed: canComplete
                ? () async {
                    Navigator.of(sheetContext).maybePop();
                    try {
                      await ref.read(taskRepositoryProvider).completeTask(task.id);
                    } catch (_) {}
                  }
                : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: '查看详情',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () {
            Navigator.of(sheetContext).maybePop();
            context.push('/task/${task.id}');
          },
          style: IconButton.styleFrom(
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _SnoozeRow extends ConsumerWidget {
  const _SnoozeRow({required this.task, required this.sheetContext});
  final Task task;
  final BuildContext sheetContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: TextButton.icon(
            icon: const Icon(Icons.snooze_rounded, size: 18),
            label: const Text('5 分钟后再提醒'),
            onPressed: () => _snooze(context, ref, const Duration(minutes: 5)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextButton.icon(
            icon: const Icon(Icons.snooze_rounded, size: 18),
            label: const Text('30 分钟后再提醒'),
            onPressed: () => _snooze(context, ref, const Duration(minutes: 30)),
          ),
        ),
      ],
    );
  }

  Future<void> _snooze(BuildContext context, WidgetRef ref, Duration d) async {
    Navigator.of(sheetContext).maybePop();
    final next = task.copyWith(remindAt: DateTime.now().add(d));
    try {
      await ref.read(taskRepositoryProvider).updateTask(next);
    } catch (_) {}
  }
}
