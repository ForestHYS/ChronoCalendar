import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ui/app_error_dialog.dart';
import '../../data/providers.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';

/// 半屏提醒弹窗：当 [Task.remindAt] 到点且 app 在前台时弹出。
///
/// 提供快捷操作：开始专注 / 标记完成 / 查看详情 / 稍后再提醒（5/30 分钟）。
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
      barrierColor: Colors.black.withValues(alpha: 0.45),
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
              Expanded(
                child: Center(
                  child: _TitleSection(task: task, theme: theme, cs: cs),
                ),
              ),
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

class _TitleSection extends StatelessWidget {
  const _TitleSection({
    required this.task,
    required this.theme,
    required this.cs,
  });

  final Task task;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final title = task.title.isEmpty ? '(未命名任务)' : task.title;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DecorativeLine(color: cs.outlineVariant),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 18),
          _DecorativeLine(color: cs.outlineVariant),
          const SizedBox(height: 12),
          _TimeLine(task: task),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              task.description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _DecorativeLine extends StatelessWidget {
  const _DecorativeLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0),
                  color.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ),
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.65), width: 1),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.55),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimeLine extends StatelessWidget {
  const _TimeLine({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = _timeText(task);
    if (text == null) return const SizedBox.shrink();

    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.45,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  static String? _timeText(Task task) {
    final df = DateFormat('MM-dd HH:mm');
    switch (task.type) {
      case TaskType.block:
        final start = task.startAt;
        final end = task.endAt;
        if (start != null && end != null) {
          return '开始 ${df.format(start)}    结束 ${df.format(end)}';
        }
        if (start != null) return '开始 ${df.format(start)}';
        if (end != null) return '结束 ${df.format(end)}';
        return null;
      case TaskType.ddl:
        if (task.dueAt != null) return '截止 ${df.format(task.dueAt!)}';
        return null;
      case TaskType.todo:
        if (task.dueAt != null) return '截止 ${df.format(task.dueAt!)}';
        if (task.expectedMinutes != null) return '预计 ${task.expectedMinutes} 分钟';
        return null;
    }
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({required this.task, required this.sheetContext});

  final Task task;
  final BuildContext sheetContext;

  static const _buttonHeight = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canComplete = task.status == TaskStatus.active ||
        task.status == TaskStatus.overdue;

    return Row(
      children: [
        Expanded(
          child: _EqualSheetButton(
            label: '开始专注',
            height: _buttonHeight,
            filled: true,
            onPressed: () => _popThenPush(context, sheetContext, '/pomodoro/${task.id}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EqualSheetButton(
            label: '标记完成',
            height: _buttonHeight,
            onPressed: canComplete
                ? () => _runAndClose(
                      sheetContext,
                      () => ref.read(taskRepositoryProvider).completeTask(task.id),
                      failureTitle: '标记完成失败',
                    )
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EqualSheetButton(
            label: '展开详情',
            height: _buttonHeight,
            onPressed: () => _popThenPush(context, sheetContext, '/task/${task.id}'),
          ),
        ),
      ],
    );
  }
}

class _EqualSheetButton extends StatelessWidget {
  const _EqualSheetButton({
    required this.label,
    required this.height,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final double height;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: filled ? null : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

    if (filled) {
      return FilledButton(
        style: style,
        onPressed: onPressed,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    return OutlinedButton(
      style: style,
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final next = task.copyWith(remindAt: DateTime.now().add(d));
    await _runAndClose(
      sheetContext,
      () => ref.read(taskRepositoryProvider).updateTask(next),
      failureTitle: '稍后提醒设置失败',
    );
  }
}

/// 跑一段会调用网络的操作：
/// - 成功 → pop 当前 sheet
/// - 失败 → 保持 sheet 在屏幕上，弹出 [showAppErrorDialog] 提示用户，便于直接重试
///
/// 注意 `sheetCtx` 必须是 sheet 内的 BuildContext。每次跨 await 前都校验 `mounted`，
/// 避免页面被其它流程提前 pop 造成 "Looking up a deactivated widget" 异常。
Future<void> _runAndClose(
  BuildContext sheetCtx,
  Future<void> Function() op, {
  required String failureTitle,
}) async {
  try {
    await op();
    if (!sheetCtx.mounted) return;
    Navigator.of(sheetCtx).maybePop();
  } catch (e) {
    if (!sheetCtx.mounted) return;
    await showAppErrorDialog(sheetCtx, error: e, title: failureTitle);
  }
}

/// 先关 sheet 再 push 路由：
/// 必须在 [Navigator.maybePop] 之前先取出 [GoRouter] 引用——pop 之后 [ctx] 的
/// element 会被 deactivated，再用它查 InheritedWidget 会触发
/// "Looking up a deactivated widget's ancestor" 异常。
void _popThenPush(BuildContext ctx, BuildContext sheetCtx, String location) {
  final router = GoRouter.of(ctx);
  Navigator.of(sheetCtx).maybePop();
  router.push(location);
}
