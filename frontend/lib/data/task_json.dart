import 'package:flutter/material.dart';

import '../core/utils/week_key.dart';
import '../domain/models/tag.dart';
import '../domain/models/task.dart';
import '../domain/models/task_status.dart';

Color parseApiColor(String hex) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  return Color(int.parse(s, radix: 16));
}

String colorToApiHex(Color c) {
  final r = (c.r * 255).round() & 0xff;
  final g = (c.g * 255).round() & 0xff;
  final b = (c.b * 255).round() & 0xff;
  final rgb = (r << 16) | (g << 8) | b;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

DateTime? _parseDt(dynamic v) {
  if (v == null) return null;
  if (v is String && v.isEmpty) return null;
  return DateTime.parse(v as String).toLocal();
}

TaskStatus _parseStatus(String s) {
  return TaskStatus.values.firstWhere(
    (e) => e.name == s,
    orElse: () => TaskStatus.active,
  );
}

TaskType _parseType(String s) {
  return TaskType.values.firstWhere((e) => e.name == s);
}

Tag tagFromJson(Map<String, dynamic> j) {
  return Tag(
    id: j['id'] as String,
    name: j['name'] as String,
    color: parseApiColor(j['color'] as String? ?? '#6366F1'),
  );
}

Task taskFromJson(Map<String, dynamic> j) {
  final status = _parseStatus(j['status'] as String);
  final subs = (j['subtasks'] as List<dynamic>?)
          ?.map((e) => subtaskFromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Subtask>[];

  final completedAt = _parseDt(j['completed_at']);
  final lastAct = _parseDt(j['last_activity_at']) ?? _parseDt(j['updated_at']) ?? DateTime.now();

  return Task(
    id: j['id'] as String,
    type: _parseType(j['type'] as String),
    title: j['title'] as String,
    description: (j['description'] as String?) ?? '',
    tagIds: (j['tag_ids'] as List<dynamic>? ?? const []).map((e) => '$e').toList(),
    status: status,
    startAt: _parseDt(j['start_at']),
    endAt: _parseDt(j['end_at']),
    dueAt: _parseDt(j['due_at']),
    expectedMinutes: j['expected_minutes'] as int?,
    remindAt: _parseDt(j['remind_at']),
    focusTotalSeconds: (j['focus_total_seconds'] as num?)?.round() ?? 0,
    subtasks: subs,
    lastActivityAt: lastAct,
    completedAtWeekYear: completedAt != null ? weekKeyFor(completedAt) : null,
  );
}

Subtask subtaskFromJson(Map<String, dynamic> j) {
  return Subtask(
    id: j['id'] as String,
    title: j['title'] as String,
    done: j['done'] as bool? ?? false,
    order: (j['order'] as num?)?.round() ?? 1,
  );
}

/// POST /tasks/ 创建体（不含 id）。
Map<String, dynamic> taskToCreateBody({
  required TaskType type,
  required String title,
  String description = '',
  List<String> tagIds = const [],
  DateTime? remindAt,
  DateTime? startAt,
  DateTime? endAt,
  DateTime? dueAt,
  int? expectedMinutes,
  List<Subtask> subtasks = const [],
}) {
  final m = <String, dynamic>{
    'type': type.name,
    'title': title,
    'description': description,
    'tag_ids': tagIds,
    if (remindAt != null) 'remind_at': remindAt.toUtc().toIso8601String(),
  };
  switch (type) {
    case TaskType.block:
      m['start_at'] = startAt!.toUtc().toIso8601String();
      m['end_at'] = endAt!.toUtc().toIso8601String();
      break;
    case TaskType.ddl:
      m['due_at'] = dueAt!.toUtc().toIso8601String();
      break;
    case TaskType.todo:
      m['due_at'] = dueAt?.toUtc().toIso8601String();
      if (expectedMinutes != null) m['expected_minutes'] = expectedMinutes;
      if (subtasks.isNotEmpty) {
        m['subtasks'] = subtasks
            .map((s) => {'title': s.title, 'order': s.order})
            .toList();
      }
      break;
  }
  return m;
}

/// PATCH /tasks/{id}/ 全量可写字段（由当前 [Task] 推导）。
Map<String, dynamic> taskToPatchBody(Task t) {
  final m = <String, dynamic>{
    'title': t.title,
    'description': t.description,
    'tag_ids': t.tagIds,
    'remind_at': t.remindAt?.toUtc().toIso8601String(),
  };
  switch (t.type) {
    case TaskType.block:
      if (t.startAt != null) m['start_at'] = t.startAt!.toUtc().toIso8601String();
      if (t.endAt != null) m['end_at'] = t.endAt!.toUtc().toIso8601String();
      break;
    case TaskType.ddl:
      m['due_at'] = t.dueAt?.toUtc().toIso8601String();
      break;
    case TaskType.todo:
      m['due_at'] = t.dueAt?.toUtc().toIso8601String();
      m['expected_minutes'] = t.expectedMinutes;
      break;
  }
  return m;
}
