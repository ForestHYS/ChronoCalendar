import 'package:flutter/foundation.dart';

import '../core/utils/week_key.dart';
import '../domain/models/tag.dart';
import '../domain/models/task.dart';
import '../domain/models/task_status.dart';
import 'mock/mock_data.dart';

class TaskRepository extends ChangeNotifier {
  TaskRepository() {
    _tags = buildInitialTags();
    _tasks = List<Task>.from(buildInitialTasks(DateTime.now()));
  }

  late List<Tag> _tags;
  late List<Task> _tasks;

  List<Tag> get tags => List.unmodifiable(_tags);
  List<Task> get tasks => List.unmodifiable(_tasks);

  Tag? tagById(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Task? taskById(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 主页「今天与明天」：block、ddl，以及带 dueAt 的 todo
  List<Task> upcomingTodayTomorrow() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 2));

    bool inRange(DateTime? d) {
      if (d == null) return false;
      return !d.isBefore(start) && d.isBefore(end);
    }

    final list = _tasks.where((t) {
      if (t.status != TaskStatus.active) return false;
      if (t.type == TaskType.block) {
        return inRange(t.startAt);
      }
      if (t.type == TaskType.ddl) {
        return inRange(t.dueAt);
      }
      if (t.type == TaskType.todo && t.dueAt != null) {
        return inRange(t.dueAt);
      }
      return false;
    }).toList();

    int sortKey(Task t) {
      final d = t.type == TaskType.block
          ? t.startAt
          : (t.type == TaskType.ddl ? t.dueAt : t.dueAt);
      return d?.millisecondsSinceEpoch ?? 0;
    }

    list.sort((a, b) => sortKey(a).compareTo(sortKey(b)));
    return list;
  }

  List<Task> todosByRecentUsage() {
    return _tasks
        .where((t) => t.type == TaskType.todo && t.status == TaskStatus.active)
        .toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
  }

  int get currentWeekKey => weekKeyFor(DateTime.now());

  int countCompletedThisWeek() {
    final wk = currentWeekKey;
    return _tasks.where((t) => t.status == TaskStatus.completed && t.completedAtWeekYear == wk).length;
  }

  int countPendingActive() {
    return _tasks.where((t) => t.status == TaskStatus.active).length;
  }

  int countCancelled() {
    return _tasks.where((t) => t.status == TaskStatus.cancelled).length;
  }

  int countOverdue() {
    return _tasks.where((t) => t.isOverdue).length;
  }

  /// 本周完成最多的标签 id（演示）
  String? topTagIdThisWeek() {
    final wk = currentWeekKey;
    final counts = <String, int>{};
    for (final t in _tasks) {
      if (t.status != TaskStatus.completed || t.completedAtWeekYear != wk) continue;
      for (final id in t.tagIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// 演示：7 天堆叠柱状数据 [dayIndex][segment] -> 相对高度
  List<List<double>> weeklyFocusStacksDemo() {
    return [
      [1.2, 0.6, 0.4],
      [0.8, 1.0, 0.2],
      [1.5, 0.3, 0.5],
      [0.4, 0.9, 0.8],
      [1.1, 0.5, 0.9],
      [0.6, 1.2, 0.3],
      [0.9, 0.7, 0.6],
    ];
  }

  void touchTask(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(lastActivityAt: DateTime.now());
    notifyListeners();
  }

  void completeTask(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(
      status: TaskStatus.completed,
      completedAtWeekYear: currentWeekKey,
      lastActivityAt: DateTime.now(),
    );
    notifyListeners();
  }

  void updateTask(Task task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i < 0) return;
    _tasks[i] = task;
    notifyListeners();
  }

  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  void toggleSubtask(String taskId, String subtaskId, bool done) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final t = _tasks[i];
    final next = t.subtasks
        .map((s) => s.id == subtaskId ? s.copyWith(done: done) : s)
        .toList();
    _tasks[i] = t.copyWith(subtasks: next, lastActivityAt: DateTime.now());
    notifyListeners();
  }

  void updateSubtaskTitle(String taskId, String subtaskId, String title) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final t = _tasks[i];
    final next = t.subtasks
        .map((s) => s.id == subtaskId ? s.copyWith(title: title) : s)
        .toList();
    _tasks[i] = t.copyWith(subtasks: next, lastActivityAt: DateTime.now());
    notifyListeners();
  }

  void addSubtask(String taskId, String title) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final t = _tasks[i];
    final maxOrder = t.subtasks.isEmpty
        ? 0
        : t.subtasks.map((s) => s.order).reduce((a, b) => a > b ? a : b);
    final id = 's_${DateTime.now().microsecondsSinceEpoch}';
    final next = [...t.subtasks, Subtask(id: id, title: title, done: false, order: maxOrder + 1)];
    _tasks[i] = t.copyWith(subtasks: next, lastActivityAt: DateTime.now());
    notifyListeners();
  }

  void removeSubtask(String taskId, String subtaskId) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final t = _tasks[i];
    final next = t.subtasks.where((s) => s.id != subtaskId).toList();
    _tasks[i] = t.copyWith(subtasks: next, lastActivityAt: DateTime.now());
    notifyListeners();
  }
}
