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

/// 时长：从左到右「大字 + 小字单位」；分钟数字略大于小时数字。
class _FocusDurationStack extends StatelessWidget {
  const _FocusDurationStack({required this.seconds, required this.tabular});

  final int seconds;
  final List<FontFeature> tabular;

  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final hourNumStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      height: 1.05,
      color: AppColors.onSurface,
      fontFeatures: tabular,
    );
    final minuteNumStyle = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.05,
      color: AppColors.onSurface,
      fontFeatures: tabular,
    );
    const unitStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      height: 1.05,
      color: AppColors.onSurfaceVariant,
    );

    if (h > 0) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$h', style: hourNumStyle),
          const SizedBox(width: 2),
          const Text('小时', style: unitStyle),
          if (m > 0) ...[
            const SizedBox(width: 6),
            Text('$m', style: minuteNumStyle),
            const SizedBox(width: 2),
            const Text('分钟', style: unitStyle),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$m', style: minuteNumStyle),
        const SizedBox(width: 2),
        const Text('分钟', style: unitStyle),
      ],
    );
  }
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
                      await showAppErrorDialog(
                        context,
                        title: '无法标记完成',
                        error: e,
                      );
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
            child: SizedBox(
              height: 196,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // ── 左卡：本周完成 ──────────────────────────────
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryContainer.withValues(alpha: 0.72),
                          AppColors.surfaceContainerHigh.withValues(
                            alpha: 0.35,
                          ),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.task_alt_rounded,
                                size: 18,
                                color: AppColors.primary.withValues(alpha: 0.9),
                              ),
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
                          const SizedBox(height: 8),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '${repo.countCompletedThisWeek()}',
                                  style: TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                    color: AppColors.onSurface,
                                    fontFeatures: tabular,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '待完成 ${repo.countPendingActive()}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: AppColors.onSurfaceVariant,
                                          height: 1.35,
                                          fontFeatures: tabular,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '已超时 ${repo.countOverdue()}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          color: AppColors.onSurfaceVariant,
                                          height: 1.35,
                                          fontFeatures: tabular,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // ── 右卡：专注统计（图表与文字并排，避免垂直溢出）──
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          const Color(0xFFE0F2FE).withValues(alpha: 0.9),
                          AppColors.surfaceContainerHigh.withValues(
                            alpha: 0.25,
                          ),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          // 标题行
                          Row(
                            children: [
                              Icon(
                                Icons.self_improvement_rounded,
                                size: 18,
                                color: AppColors.primary.withValues(
                                  alpha: 0.85,
                                ),
                              ),
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
                          // 内容行：时长 & 图例（左）+ 甜甜圈图（右）
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        '近7日专注',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.onSurfaceVariant,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      _FocusDurationStack(
                                        seconds: lastWeekTotal,
                                        tabular: tabular,
                                      ),
                                      const SizedBox(height: 8),
                                      for (final s in focusSlices.where((s) => s.seconds > 0))
                                        _FocusLegendLine(repo: repo, slice: s),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TagFocusDonutChart(
                                  slices: focusSlices,
                                  resolveTag: repo.tagById,
                                  dimension: 80,
                                  repaint: repo,
                                ),
                              ],
                            ),
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
    final tag = slice.tagId == '__untagged__' ? null : repo.tagById(slice.tagId);
    final Color dotColor;
    final String labelText;
    if (slice.tagId == '__untagged__') {
      dotColor = const Color(0xFF0D9488);
      labelText = '无标签';
    } else if (tag == null) {
      return const SizedBox.shrink();
    } else {
      dotColor = tag.color;
      labelText = tag.name;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 88),
            child: Text(
              labelText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                height: 1.2,
              ),
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
    final t =
        ref.watch(taskRepositoryProvider).taskById(widget.task.id) ??
        widget.task;
    final canComplete = t.subtasks.isEmpty || t.subtasks.every((s) => s.done);
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
                    t.expectedMinutes != null
                        ? '预计 ${t.expectedMinutes} 分钟'
                        : 'todo',
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
                            await showAppErrorDialog(
                              context,
                              title: '更新失败',
                              error: e,
                            );
                          }
                        }());
                      },
                      title: Text(
                        s.title,
                        style: const TextStyle(fontSize: 13.5, height: 1.25),
                      ),
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
                      side: BorderSide(
                        color: AppColors.outline.withValues(alpha: 0.9),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '详情',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () {
                      widget.repo.touchTask(t.id);
                      context.push('/pomodoro/${t.id}');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(
                        color: AppColors.primary,
                        width: 1,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '专注',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (canComplete) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        unawaited(() async {
                          try {
                            await widget.repo.completeTask(t.id);
                          } catch (e) {
                            if (!context.mounted) return;
                            await showAppErrorDialog(
                              context,
                              title: '无法完成',
                              error: e,
                            );
                          }
                        }());
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(
                          color: AppColors.success,
                          width: 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
