// TODO: 接入 GET /tasks 筛选排序与侧边类型栏（block / ddl / todo）、顶栏搜索与标签筛选。

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('任务列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_outlined),
            onPressed: () {},
            tooltip: '筛选/排序',
          ),
        ],
      ),
      body: const Center(
        child: Text(
          '任务列表框架已就绪',
          style: TextStyle(color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
