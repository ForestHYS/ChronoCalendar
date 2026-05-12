import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/task.dart';
import 'widgets/task_category_rail.dart';
import 'widgets/task_list_search_field.dart';

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

  @override
  Widget build(BuildContext context) {
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
            child: Center(
              child: Text(
                '已选 ${_category?.name ?? '全部'}'
                '${_searchQuery.isEmpty ? '' : ' · 关键词「$_searchQuery」'}',
                style: const TextStyle(color: AppColors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
