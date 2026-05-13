import '../../../domain/models/task.dart';
import '../../../domain/models/task_status.dart';

/// 任务列表的排序方式。不同类别可用的子集见 [sortOptionsFor]。
enum TaskSortOption {
  recentActivity('最近活动'),
  startAtAsc('开始时间 ↑'),
  startAtDesc('开始时间 ↓'),
  dueAtAsc('截止时间 ↑'),
  dueAtDesc('截止时间 ↓'),
  focusSpentDesc('已专注时长 ↓'),
  focusSpentAsc('已专注时长 ↑');

  const TaskSortOption(this.label);
  final String label;
}

/// 当前类别下用户可选的排序方式。
///
/// - 全部：仅 recentActivity（不同类型时间字段不可比）
/// - block：recentActivity + start_at 升降
/// - ddl：recentActivity + due_at 升降
/// - todo：recentActivity + due_at 升降 + 已专注时长升降
List<TaskSortOption> sortOptionsFor(TaskType? category) {
  switch (category) {
    case null:
      return const [TaskSortOption.recentActivity];
    case TaskType.block:
      return const [
        TaskSortOption.recentActivity,
        TaskSortOption.startAtAsc,
        TaskSortOption.startAtDesc,
      ];
    case TaskType.ddl:
      return const [
        TaskSortOption.recentActivity,
        TaskSortOption.dueAtAsc,
        TaskSortOption.dueAtDesc,
      ];
    case TaskType.todo:
      return const [
        TaskSortOption.recentActivity,
        TaskSortOption.dueAtAsc,
        TaskSortOption.dueAtDesc,
        TaskSortOption.focusSpentDesc,
        TaskSortOption.focusSpentAsc,
      ];
  }
}

/// 任务列表的筛选与排序状态（由 TaskListPage 维护，传给筛选面板）。
class TaskFilterState {
  TaskFilterState({
    this.sort = TaskSortOption.recentActivity,
    Set<TaskStatus>? statuses,
    Set<String>? tagIds,
  })  : statuses = statuses ?? <TaskStatus>{},
        tagIds = tagIds ?? <String>{};

  TaskSortOption sort;

  /// 空集合表示「全部状态」。
  Set<TaskStatus> statuses;

  /// 空集合表示「全部标签」。
  Set<String> tagIds;

  bool get hasActiveFilters => statuses.isNotEmpty || tagIds.isNotEmpty;

  TaskFilterState copy() => TaskFilterState(
        sort: sort,
        statuses: {...statuses},
        tagIds: {...tagIds},
      );
}
