import 'task_status.dart';

enum TaskType { block, ddl, todo }

class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    required this.done,
    required this.order,
  });

  final String id;
  final String title;
  final bool done;
  final int order;

  Subtask copyWith({String? title, bool? done, int? order}) {
    return Subtask(
      id: id,
      title: title ?? this.title,
      done: done ?? this.done,
      order: order ?? this.order,
    );
  }
}

class Task {
  const Task({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    required this.tagIds,
    required this.status,
    this.startAt,
    this.endAt,
    this.dueAt,
    this.expectedMinutes,
    this.remindAt,
    this.focusTotalSeconds = 0,
    this.subtasks = const [],
    required this.lastActivityAt,
    this.completedAtWeekYear,
  });

  final String id;
  final TaskType type;
  final String title;
  final String description;
  final List<String> tagIds;
  final TaskStatus status;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? dueAt;
  final int? expectedMinutes;
  final DateTime? remindAt;
  final int focusTotalSeconds;
  final List<Subtask> subtasks;
  final DateTime lastActivityAt;

  /// 用于统计「本周完成」：完成时记录所属 ISO week-year
  final int? completedAtWeekYear;

  bool get isOverdue {
    if (status == TaskStatus.overdue) return true;
    if (status != TaskStatus.active) return false;
    final now = DateTime.now();
    if (type == TaskType.block && endAt != null) {
      return endAt!.isBefore(now);
    }
    if (type == TaskType.ddl && dueAt != null) {
      return dueAt!.isBefore(now);
    }
    if (type == TaskType.todo && dueAt != null) {
      return dueAt!.isBefore(now);
    }
    return false;
  }

  Task copyWith({
    TaskType? type,
    String? title,
    String? description,
    List<String>? tagIds,
    TaskStatus? status,
    DateTime? startAt,
    DateTime? endAt,
    DateTime? dueAt,
    int? expectedMinutes,
    DateTime? remindAt,
    int? focusTotalSeconds,
    List<Subtask>? subtasks,
    DateTime? lastActivityAt,
    int? completedAtWeekYear,
    bool clearDueAt = false,
    bool clearRemindAt = false,
    bool clearStartAt = false,
    bool clearEndAt = false,
    bool clearExpectedMinutes = false,
  }) {
    return Task(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      tagIds: tagIds ?? this.tagIds,
      status: status ?? this.status,
      startAt: clearStartAt ? null : (startAt ?? this.startAt),
      endAt: clearEndAt ? null : (endAt ?? this.endAt),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      expectedMinutes: clearExpectedMinutes ? null : (expectedMinutes ?? this.expectedMinutes),
      remindAt: clearRemindAt ? null : (remindAt ?? this.remindAt),
      focusTotalSeconds: focusTotalSeconds ?? this.focusTotalSeconds,
      subtasks: subtasks ?? this.subtasks,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      completedAtWeekYear: completedAtWeekYear ?? this.completedAtWeekYear,
    );
  }
}
