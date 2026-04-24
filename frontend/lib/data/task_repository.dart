import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/utils/week_key.dart';
import '../domain/models/tag.dart';
import '../domain/models/task.dart';
import '../domain/models/task_status.dart';
import 'task_json.dart';

/// 演示：上周某标签专注时长（秒）；后端暂无统计接口时返回空。
class TagFocusSlice {
  const TagFocusSlice(this.tagId, this.seconds);
  final String tagId;
  final int seconds;
}

class TaskRepository extends ChangeNotifier {
  TaskRepository(this._api);

  final ApiClient _api;

  List<Tag> _tags = [];
  List<Task> _tasks = [];

  List<Tag> get tags => List.unmodifiable(_tags);
  List<Task> get tasks => List.unmodifiable(_tasks);

  /// 登录后拉取标签与任务列表。
  Future<void> bootstrap() async {
    await refreshTags();
    await refreshTasks();
  }

  Future<void> refreshTags() async {
    final data = await _api.request('GET', 'tags/', auth: true);
    if (data is List) {
      _tags = data.map((e) => tagFromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> refreshTasks() async {
    final all = <Task>[];
    var page = 1;
    const pageSize = 100;
    while (true) {
      final data = await _api.request(
        'GET',
        'tasks/?page=$page&page_size=$pageSize',
        auth: true,
      );
      if (data is! Map<String, dynamic>) break;
      final items = data['items'] as List<dynamic>? ?? const [];
      for (final e in items) {
        all.add(taskFromJson(e as Map<String, dynamic>));
      }
      final total = (data['total'] as num?)?.round() ?? 0;
      if (all.length >= total || items.isEmpty) break;
      page++;
    }
    _tasks = all;
    notifyListeners();
  }

  Future<void> ensureTaskLoaded(String id) async {
    if (taskById(id) != null) return;
    final data = await _api.request('GET', 'tasks/$id/', auth: true);
    if (data is Map<String, dynamic>) {
      final t = taskFromJson(data);
      _tasks = [..._tasks, t];
      notifyListeners();
    }
  }

  Tag? tagById(String id) {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addTag({required String name, required Color color}) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final data = await _api.request(
      'POST',
      'tags/',
      body: {'name': n, 'color': colorToApiHex(color)},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      _tags = [..._tags, tagFromJson(data)];
      notifyListeners();
    }
  }

  Future<void> renameTag(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final data = await _api.request(
      'PATCH',
      'tags/$id/',
      body: {'name': n},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final tag = tagFromJson(data);
      _tags = _tags.map((t) => t.id == id ? tag : t).toList();
      notifyListeners();
    }
  }

  Future<void> recolorTag(String id, Color color) async {
    final data = await _api.request(
      'PATCH',
      'tags/$id/',
      body: {'color': colorToApiHex(color)},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final tag = tagFromJson(data);
      _tags = _tags.map((t) => t.id == id ? tag : t).toList();
      notifyListeners();
    }
  }

  Future<void> deleteTag(String id) async {
    await _api.request('DELETE', 'tags/$id/', auth: true);
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

  bool _isActiveOrOverdue(Task t) =>
      t.status == TaskStatus.active || t.status == TaskStatus.overdue;

  /// 主页「今天与明天」
  List<Task> upcomingTodayTomorrow() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 2));

    bool inRange(DateTime? d) {
      if (d == null) return false;
      return !d.isBefore(start) && d.isBefore(end);
    }

    final list = _tasks.where((t) {
      if (!_isActiveOrOverdue(t)) return false;
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

  List<Task> recentTasksForHome({int limit = 3}) {
    return upcomingTodayTomorrow().take(limit).toList();
  }

  List<Task> todosByRecentUsage() {
    return _tasks
        .where((t) => t.type == TaskType.todo && _isActiveOrOverdue(t))
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
    return _tasks.where((t) => _isActiveOrOverdue(t)).length;
  }

  int countCancelled() {
    return _tasks.where((t) => t.status == TaskStatus.cancelled).length;
  }

  int countOverdue() {
    return _tasks.where((t) => t.isOverdue || t.status == TaskStatus.overdue).length;
  }

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

  List<TagFocusSlice> lastWeekFocusSecondsByTag() {
    return const [];
  }

  int lastWeekTotalFocusSeconds() {
    return 0;
  }

  void touchTask(String id) {}

  Future<void> completeTask(String id) async {
    final data = await _api.request('POST', 'tasks/$id/complete/', auth: true);
    if (data is Map<String, dynamic>) {
      _replaceTask(taskFromJson(data));
    }
  }

  Future<void> updateTask(Task task) async {
    final data = await _api.request(
      'PATCH',
      'tasks/${task.id}/',
      body: taskToPatchBody(task),
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      _replaceTask(taskFromJson(data));
    }
  }

  Future<void> deleteTask(String id) async {
    await _api.request('DELETE', 'tasks/$id/', auth: true);
    _tasks = _tasks.where((t) => t.id != id).toList();
    notifyListeners();
  }

  /// 新建服务端任务（默认 block），返回任务 id。
  Future<String> createDraftTask(TaskType type) async {
    final now = DateTime.now();
    DateTime? startAt;
    DateTime? endAt;
    DateTime? dueAt;
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
    final body = taskToCreateBody(
      type: type,
      title: '新任务',
      description: '',
      tagIds: const [],
      startAt: startAt,
      endAt: endAt,
      dueAt: dueAt,
    );
    final data = await _api.request('POST', 'tasks/', body: body, auth: true);
    if (data is! Map<String, dynamic>) {
      throw StateError('创建任务失败');
    }
    final task = taskFromJson(data);
    _tasks = [..._tasks, task];
    notifyListeners();
    return task.id;
  }

  /// 删除旧任务并以 [next] 的字段新建为 [next.type]（类型不可 PATCH 时用于切换）。
  Future<String> replaceTaskWithNewType(Task next) async {
    final oldId = next.id;
    await deleteTask(oldId);
    final body = taskToCreateBody(
      type: next.type,
      title: next.title,
      description: next.description,
      tagIds: next.tagIds,
      remindAt: next.remindAt,
      startAt: next.startAt,
      endAt: next.endAt,
      dueAt: next.dueAt,
      expectedMinutes: next.expectedMinutes,
      subtasks: next.subtasks,
    );
    final data = await _api.request('POST', 'tasks/', body: body, auth: true);
    if (data is! Map<String, dynamic>) {
      throw StateError('创建任务失败');
    }
    final created = taskFromJson(data);
    _tasks = [..._tasks, created];
    notifyListeners();
    return created.id;
  }

  Future<void> toggleSubtask(String taskId, String subtaskId, bool done) async {
    final data = await _api.request(
      'PATCH',
      'subtasks/$subtaskId/',
      body: {'done': done},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      _mergeSubtaskFromApi(taskId, data);
    }
  }

  Future<void> updateSubtaskTitle(String taskId, String subtaskId, String title) async {
    final data = await _api.request(
      'PATCH',
      'subtasks/$subtaskId/',
      body: {'title': title},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      _mergeSubtaskFromApi(taskId, data);
    }
  }

  Future<void> addSubtask(String taskId, String title) async {
    final t = taskById(taskId);
    if (t == null || t.type != TaskType.todo) return;
    final maxOrder = t.subtasks.isEmpty
        ? 0
        : t.subtasks.map((s) => s.order).reduce((a, b) => a > b ? a : b);
    final data = await _api.request(
      'POST',
      'tasks/$taskId/subtasks/',
      body: {'title': title, 'order': maxOrder + 1},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final sub = subtaskFromJson(data);
      final nextSubs = [...t.subtasks, sub];
      _replaceTask(t.copyWith(subtasks: nextSubs, lastActivityAt: DateTime.now()));
    }
  }

  Future<void> removeSubtask(String taskId, String subtaskId) async {
    await _api.request('DELETE', 'subtasks/$subtaskId/', auth: true);
    final t = taskById(taskId);
    if (t == null) return;
    final next = t.subtasks.where((s) => s.id != subtaskId).toList();
    _replaceTask(t.copyWith(subtasks: next, lastActivityAt: DateTime.now()));
  }

  void _replaceTask(Task task) {
    final i = _tasks.indexWhere((x) => x.id == task.id);
    if (i >= 0) {
      final copy = List<Task>.from(_tasks);
      copy[i] = task;
      _tasks = copy;
    } else {
      _tasks = [..._tasks, task];
    }
    notifyListeners();
  }

  void clearLocalCache() {
    _tags = [];
    _tasks = [];
    notifyListeners();
  }

  void _mergeSubtaskFromApi(String taskId, Map<String, dynamic> subJson) {
    final sub = subtaskFromJson(subJson);
    final t = taskById(taskId);
    if (t == null) return;
    final next = List<Subtask>.from(t.subtasks);
    final idx = next.indexWhere((s) => s.id == sub.id);
    if (idx >= 0) {
      next[idx] = sub;
    } else {
      next.add(sub);
    }
    _replaceTask(t.copyWith(subtasks: next, lastActivityAt: DateTime.now()));
  }
}
