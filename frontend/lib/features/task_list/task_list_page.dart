import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';
import 'widgets/task_category_rail.dart';
import 'widgets/task_filter_sort_sheet.dart';
import 'widgets/task_filter_state.dart';
import 'widgets/task_list_search_field.dart';
import 'widgets/task_row_card.dart';

class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  TaskType? _category;
  TaskFilterState _filter = TaskFilterState();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onCategoryChanged(TaskType? next) {
    setState(() {
      _category = next;
      // 切换类别后若当前排序对新类别不适用，回退到默认。
      if (!sortOptionsFor(next).contains(_filter.sort)) {
        _filter.sort = TaskSortOption.recentActivity;
      }
    });
  }

  Future<void> _openFilterSheet() async {
    final tags = ref.read(taskRepositoryProvider).tags;
    final result = await showTaskFilterSortSheet(
      context: context,
      current: _filter,
      category: _category,
      availableTags: tags,
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  TaskStatus _effectiveStatus(Task t) {
    if (t.status == TaskStatus.active && t.isOverdue) return TaskStatus.overdue;
    return t.status;
  }

  List<Tag> _tagsFor(TaskRepository repo, Task t) =>
      t.tagIds.map(repo.tagById).whereType<Tag>().toList();

  List<Task> _visibleTasks(TaskRepository repo) {
    final q = _searchQuery.toLowerCase();
    final out = repo.tasks.where((t) {
      if (_category != null && t.type != _category) return false;
      if (q.isNotEmpty && !t.title.toLowerCase().contains(q)) return false;
      if (_filter.statuses.isNotEmpty &&
          !_filter.statuses.contains(_effectiveStatus(t))) {
        return false;
      }
      if (_filter.tagIds.isNotEmpty &&
          !t.tagIds.any(_filter.tagIds.contains)) {
        return false;
      }
      return true;
    }).toList();
    out.sort((a, b) => _compareTasks(a, b, _filter.sort));
    return out;
  }

  static int _compareTasks(Task a, Task b, TaskSortOption sort) {
    switch (sort) {
      case TaskSortOption.recentActivity:
        return b.lastActivityAt.compareTo(a.lastActivityAt);
      case TaskSortOption.startAtAsc:
        return _cmpDate(a.startAt, b.startAt, asc: true);
      case TaskSortOption.startAtDesc:
        return _cmpDate(a.startAt, b.startAt, asc: false);
      case TaskSortOption.dueAtAsc:
        return _cmpDate(a.dueAt, b.dueAt, asc: true);
      case TaskSortOption.dueAtDesc:
        return _cmpDate(a.dueAt, b.dueAt, asc: false);
      case TaskSortOption.focusSpentDesc:
        return b.focusTotalSeconds.compareTo(a.focusTotalSeconds);
      case TaskSortOption.focusSpentAsc:
        return a.focusTotalSeconds.compareTo(b.focusTotalSeconds);
    }
  }

  /// 缺失日期统一排到最后，保证升序/降序时 null 不抢占头部。
  static int _cmpDate(DateTime? a, DateTime? b, {required bool asc}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return asc ? a.compareTo(b) : b.compareTo(a);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(taskRepositoryProvider);
    final tasks = _visibleTasks(repo);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 12,
        title: TaskListSearchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v.trim()),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => context.push('/agent'),
            tooltip: 'AI 助手',
          ),
          _FilterButton(
            active: _filter.hasActiveFilters,
            onPressed: _openFilterSheet,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          TaskCategoryRail(
            selected: _category,
            onSelected: _onCategoryChanged,
          ),
          Expanded(
            child: tasks.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: tasks.length,
                    itemBuilder: (context, i) {
                      final t = tasks[i];
                      return TaskRowCard(
                        task: t,
                        tags: _tagsFor(repo, t),
                        onTap: () {
                          repo.touchTask(t.id);
                          context.push('/task/${t.id}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.tune_outlined),
          onPressed: onPressed,
          tooltip: '筛选/排序',
        ),
        if (active)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: AppColors.onSurfaceVariant),
            SizedBox(height: 8),
            Text(
              '没有匹配的任务',
              style: TextStyle(color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
