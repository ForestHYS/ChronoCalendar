import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../shared/widgets/app_card.dart';
import 'widgets/title_with_tags_row.dart';
import 'widgets/recent_task_card.dart';
import 'widgets/tag_focus_donut_chart.dart';

String _formatFocusDurationCn(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h >= 1 && m > 0) {
    return '$h小时$m分';
  }
  if (h >= 1) {
    return '$h小时';
  }
  if (m > 0) {
    return '$m分钟';
  }
  return '0分钟';
}

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

List<Tag> _tagsForTask(TaskRepository repo, Task t) {
  return t.tagIds.map(repo.tagById).whereType<Tag>().toList();
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(taskRepositoryProvider);
    final recent = repo.recentTasksForHome(limit: 3);
    final todos = repo.todosByRecentUsage();
    final topTagId = repo.topTagIdThisWeek();
    final topTag = topTagId != null ? repo.tagById(topTagId) : null;
    final tabular = const [FontFeature.tabularFigures()];
    final focusSlices = repo.lastWeekFocusSecondsByTag();
    final lastWeekTotal = repo.lastWeekTotalFocusSeconds();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('主页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'AI 助手',
            onPressed: () => context.push('/agent'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('最近任务', style: AppTextStyles.homeSectionTitle),
          ),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            const AppCard(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '暂无安排',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              ),
            )
          else
            ...recent.map((t) {
              final tags = _tagsForTask(repo, t);
              return RecentTaskCard(
                task: t,
                tags: tags,
                subtitle: _upcomingSubtitle(t),
                onTap: () {
                  repo.touchTask(t.id);
                  context.push('/task/${t.id}');
                },
                onFocus: () {
                  repo.touchTask(t.id);
                      context.push('/pomodoro/${t.id}');
                },
                onDismissedComplete: () {
                  unawaited(() async {
                    try {
                      await repo.completeTask(t.id);
                    } catch (e) {
                      if (!context.mounted) return;
                      await showAppErrorDialog(context, title: '无法标记完成', error: e);
                    }
                  }());
                },
              );
            }),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Todo', style: AppTextStyles.homeSectionTitle),
          ),
          const SizedBox(height: 8),
          ...todos.map((t) => _TodoExpandTile(task: t, repo: repo)),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('统计', style: AppTextStyles.homeSectionTitle),
          ),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryContainer.withValues(alpha: 0.72),
                            AppColors.surfaceContainerHigh.withValues(alpha: 0.35),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.outline.withValues(alpha: 0.55)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.task_alt_rounded, size: 18, color: AppColors.primary.withValues(alpha: 0.9)),
                                const SizedBox(width: 6),
                                const Text(
                                  '本周完成',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${repo.countCompletedThisWeek()}',
                              style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                color: AppColors.onSurface,
                                fontFeatures: tabular,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '待完成 ${repo.countPendingActive()}  ·  已取消 ${repo.countCancelled()}  ·  已超时 ${repo.countOverdue()}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.onSurfaceVariant,
                                height: 1.4,
                                fontFeatures: tabular,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Text(
                                  '本周最多标签',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (topTag != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(AppRadii.chip),
                                      border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
                                    ),
                                    child: Text(
                                      topTag.name,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E40AF),
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    '—',
                                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            const Color(0xFFE0F2FE).withValues(alpha: 0.9),
                            AppColors.surfaceContainerHigh.withValues(alpha: 0.25),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: AppColors.outline.withValues(alpha: 0.55)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.self_improvement_rounded, size: 18, color: AppColors.primary.withValues(alpha: 0.85)),
                                const SizedBox(width: 6),
                                const Text(
                                  '专注统计',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      TagFocusDonutChart(
                                        slices: focusSlices,
                                        resolveTag: repo.tagById,
                                        dimension: 88,
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        '上周总专注时长',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.onSurfaceVariant,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatFocusDurationCn(lastWeekTotal),
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          height: 1.05,
                                          color: AppColors.onSurface,
                                          fontFeatures: tabular,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 104, maxHeight: 120),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        for (final s in focusSlices)
                                          _FocusLegendLine(repo: repo, slice: s),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusLegendLine extends StatelessWidget {
  const _FocusLegendLine({required this.repo, required this.slice});

  final TaskRepository repo;
  final TagFocusSlice slice;

  @override
  Widget build(BuildContext context) {
    final tag = repo.tagById(slice.tagId);
    if (tag == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tag.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 88),
            child: Text(
              tag.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant, height: 1.2),
            ),
          ),
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
    final tags = _tagsForTask(widget.repo, t);
    final tileTheme = Theme.of(context).copyWith(
      dividerColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity(horizontal: 0, vertical: -2),
        minVerticalPadding: 0,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: tileTheme,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          childrenPadding: EdgeInsets.zero,
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          collapsedBackgroundColor: AppColors.surfaceContainer,
          backgroundColor: AppColors.surfaceContainer,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TitleWithTagsRow(
                title: t.title,
                tags: tags,
                titleStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurface,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.expectedMinutes != null ? '预计 ${t.expectedMinutes} 分钟' : 'todo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          onExpansionChanged: (open) {
            if (open) widget.repo.touchTask(t.id);
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
              child: Column(
                children: [
                  for (final s in t.subtasks)
                    CheckboxListTile(
                      value: s.done,
                      onChanged: (v) {
                        if (v == null) return;
                        unawaited(() async {
                          try {
                            await widget.repo.toggleSubtask(t.id, s.id, v);
                          } catch (e) {
                            if (!context.mounted) return;
                            await showAppErrorDialog(context, title: '更新失败', error: e);
                          }
                        }());
                      },
                      title: Text(s.title, style: const TextStyle(fontSize: 13.5, height: 1.25)),
                      controlAffinity: ListTileControlAffinity.leading,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      widget.repo.touchTask(t.id);
                      context.push('/task/${t.id}');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceVariant,
                      side: BorderSide(color: AppColors.outline.withValues(alpha: 0.9)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('详情', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () {
                      widget.repo.touchTask(t.id);
                      context.push('/pomodoro/${t.id}');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('专注', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  if (allDone) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        unawaited(() async {
                          try {
                            await widget.repo.completeTask(t.id);
                          } catch (e) {
                            if (!context.mounted) return;
                            await showAppErrorDialog(context, title: '无法完成', error: e);
                          }
                        }());
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(color: AppColors.success, width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('完成', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
