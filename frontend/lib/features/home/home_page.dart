import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/task_row_upcoming.dart';
import 'widgets/simple_bar_chart.dart';

String _upcomingSubtitle(Task t) {
  switch (t.type) {
    case TaskType.block:
      final a = DateFormat('M/d HH:mm').format(t.startAt!);
      final b = DateFormat('HH:mm').format(t.endAt!);
      return '$a – $b · block';
    case TaskType.ddl:
      return '${DateFormat('M/d HH:mm').format(t.dueAt!)} 截止 · ddl';
    case TaskType.todo:
      return '${DateFormat('M/d HH:mm').format(t.dueAt!)} · todo';
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(taskRepositoryProvider);
    final upcoming = repo.upcomingTodayTomorrow();
    final todos = repo.todosByRecentUsage();
    final stacks = repo.weeklyFocusStacksDemo();
    final topTagId = repo.topTagIdThisWeek();
    final topTag = topTagId != null ? repo.tagById(topTagId) : null;
    final tabular = const [FontFeature.tabularFigures()];

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          '主页',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          Text(
            '今天与明天',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            const AppCard(
              padding: EdgeInsets.all(20),
              child: Text(
                '暂无安排',
                style: TextStyle(color: AppColors.onSurfaceVariant),
              ),
            )
          else
            ...upcoming.map((t) {
              final tag = t.tagIds.isNotEmpty ? repo.tagById(t.tagIds.first) : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TaskRowUpcoming(
                  task: t,
                  subtitle: _upcomingSubtitle(t),
                  tag: tag,
                  onTap: () {
                    repo.touchTask(t.id);
                    context.push('/task/${t.id}');
                  },
                  onFocus: () {
                    repo.touchTask(t.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('番茄钟页面开发中')),
                    );
                  },
                  onComplete: () => repo.completeTask(t.id),
                ),
              );
            }),
          const SizedBox(height: 20),
          Text(
            '统计',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本周完成',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${repo.countCompletedThisWeek()}',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: AppColors.onSurface,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '待完成 ${repo.countPendingActive()}  ·  已取消 ${repo.countCancelled()}  ·  已超时 ${repo.countOverdue()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                    height: 1.45,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      '本周最多标签',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (topTag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadii.chip),
                        ),
                        child: Text(
                          topTag.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      )
                    else
                      const Text(
                        '—',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: SimpleBarChart(stacks: stacks),
          ),
          const SizedBox(height: 20),
          Text(
            'Todo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          ...todos.map((t) => _TodoExpandTile(task: t, repo: repo)),
        ],
      ),
    );
  }
}

class _TodoExpandTile extends ConsumerStatefulWidget {
  const _TodoExpandTile({required this.task, required this.repo});

  final Task task;
  final TaskRepository repo;

  @override
  ConsumerState<_TodoExpandTile> createState() => _TodoExpandTileState();
}

class _TodoExpandTileState extends ConsumerState<_TodoExpandTile> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(taskRepositoryProvider).taskById(widget.task.id) ?? widget.task;
    final allDone = t.subtasks.isNotEmpty && t.subtasks.every((s) => s.done);
    final tag = t.tagIds.isNotEmpty ? widget.repo.tagById(t.tagIds.first) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          t.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
        ),
        subtitle: Text(
          t.expectedMinutes != null ? '预计 ${t.expectedMinutes} 分钟' : 'todo',
          style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant),
        ),
        onExpansionChanged: (open) {
          if (open) widget.repo.touchTask(t.id);
        },
        children: [
          if (tag != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _MiniTagLabel(tag: tag),
              ),
            ),
          ...t.subtasks.map((s) {
            return CheckboxListTile(
              value: s.done,
              onChanged: (v) {
                if (v != null) widget.repo.toggleSubtask(t.id, s.id, v);
              },
              title: Text(s.title, style: const TextStyle(fontSize: 14)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    widget.repo.touchTask(t.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('番茄钟页面开发中')),
                    );
                  },
                  child: const Text('专注'),
                ),
                if (allDone)
                  TextButton(
                    onPressed: () => widget.repo.completeTask(t.id),
                    style: TextButton.styleFrom(foregroundColor: AppColors.success),
                    child: const Text('完成'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _MiniTagLabel extends StatelessWidget {
  const _MiniTagLabel({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          tag.name,
          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
      ],
    );
  }
}
