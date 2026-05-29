import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/task.dart';

class TodoTimelinePanel extends StatelessWidget {
  const TodoTimelinePanel({
    super.key,
    required this.todos,
    required this.repo,
    required this.expanded,
    required this.onToggle,
  });

  final List<Task> todos;
  final TaskRepository repo;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '未完成 Todo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${todos.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E40AF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildExpandedBody(context),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context) {
    if (todos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          '当前没有未完成的 Todo',
          style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12.5),
        ),
      );
    }

    final viewHeight = MediaQuery.sizeOf(context).height;
    final maxListHeight = (viewHeight * 0.38).clamp(140.0, 320.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxListHeight),
      child: Scrollbar(
        thumbVisibility: todos.length > 4,
        child: ListView.builder(
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: todos.length,
          itemBuilder: (context, index) {
            final todo = todos[index];
            return _TodoLine(
              task: todo,
              onTap: () => context.push('/task/${todo.id}'),
            );
          },
        ),
      ),
    );
  }
}

class _TodoLine extends StatelessWidget {
  const _TodoLine({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = task.subtasks.length;
    final done = task.subtasks.where((s) => s.done).length;
    final progress = total == 0 ? 0.0 : done / total;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              total == 0 ? '0/0' : '$done/$total',
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
