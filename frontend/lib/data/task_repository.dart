import 'package:flutter/material.dart';

import '../core/utils/week_key.dart';
import '../domain/models/tag.dart';
import '../domain/models/task.dart';
import '../domain/models/task_status.dart';
import 'mock/mock_data.dart';

/// 演示：上周某标签专注时长（秒），供环图使用。
class TagFocusSlice {
  const TagFocusSlice(this.tagId, this.seconds);
  final String tagId;
  final int seconds;
}

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

  void addTag({required String name, required Color color}) {
    final n = name.trim();
    if (n.isEmpty) return;
    final id = 'tag_${DateTime.now().microsecondsSinceEpoch}';
    _tags = [..._tags, Tag(id: id, name: n, color: color)];
    notifyListeners();
  }

  void renameTag(String id, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    _tags = _tags.map((t) => t.id == id ? Tag(id: t.id, name: n, color: t.color) : t).toList();
    notifyListeners();
  }

  void recolorTag(String id, Color color) {
    _tags = _tags.map((t) => t.id == id ? Tag(id: t.id, name: t.name, color: color) : t).toList();
    notifyListeners();
  }

  void deleteTag(String id) {
    _tags = _tags.where((t) => t.id != id).toList();
    _tasks = _tasks.map((t) {
      if (!t.tagIds.contains(id)) return t;
      return t.copyWith(tagIds: t.tagIds.where((x) => x != id).toList());
    }).toList();
    notifyListeners();
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

  /// 主页「最近任务」：与 [upcomingTodayTomorrow] 同规则，最多 [limit] 条。
  List<Task> recentTasksForHome({int limit = 3}) {
    return upcomingTodayTomorrow().take(limit).toList();
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

  int countCompletedTotal() {
    return _tasks.where((t) => t.status == TaskStatus.completed).length;
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

  /// 演示：上周按标签的专注秒数（// TODO: 对接真实统计接口）。
  List<TagFocusSlice> lastWeekFocusSecondsByTag() {
    return const [
      TagFocusSlice('tag_learn', 12600),
      TagFocusSlice('tag_work', 9000),
      TagFocusSlice('tag_life', 4200),
      TagFocusSlice('tag_other', 2100),
    ];
  }

  /// 演示：上周总专注时长（秒）。
  int lastWeekTotalFocusSeconds() {
    return lastWeekFocusSecondsByTag().fold(0, (a, b) => a + b.seconds);
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

  /// 新建草稿任务，返回 id 供详情/编辑页复用同一套 UI。
  String createDraftTask(TaskType type) {
    final id = 't_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now();
    DateTime? startAt;
    DateTime? endAt;
    DateTime? dueAt;
    const subs = <Subtask>[];
    switch (type) {
      case TaskType.block:
        startAt = now;
        endAt = now.add(const Duration(hours: 1));
        break;
      case TaskType.ddl:
        dueAt = now.add(const Duration(days: 1));
        break;
      case TaskType.todo:
        dueAt = now.add(const Duration(days: 1));
        break;
    }
    final task = Task(
      id: id,
      type: type,
      title: '新任务',
      description: '',
      tagIds: const [],
      status: TaskStatus.active,
      lastActivityAt: now,
      startAt: startAt,
      endAt: endAt,
      dueAt: dueAt,
      subtasks: subs,
    );
    _tasks = [..._tasks, task];
    notifyListeners();
    return id;
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
