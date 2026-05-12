import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../../data/task_repository.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import 'widgets/task_category_rail.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Tag> _tagsFor(TaskRepository repo, Task t) =>
      t.tagIds.map(repo.tagById).whereType<Tag>().toList();

  List<Task> _visibleTasks(TaskRepository repo) {
    final q = _searchQuery.toLowerCase();
    final out = repo.tasks.where((t) {
      if (_category != null && t.type != _category) return false;
      if (q.isNotEmpty && !t.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    out.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return out;
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
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            onPressed: () {},
            tooltip: '筛选/排序',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          TaskCategoryRail(
            selected: _category,
            onSelected: (v) => setState(() => _category = v),
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
