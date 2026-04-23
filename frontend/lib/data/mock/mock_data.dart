import 'package:flutter/material.dart';

import '../../core/utils/week_key.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/models/task_status.dart';

List<Tag> buildInitialTags() {
  return const [
    Tag(id: 'tag_learn', name: '学习', color: Color(0xFF3B82F6)),
    Tag(id: 'tag_work', name: '工作', color: Color(0xFF8B5CF6)),
    Tag(id: 'tag_life', name: '生活', color: Color(0xFFF59E0B)),
    Tag(id: 'tag_other', name: '其它', color: Color(0xFFEC4899)),
  ];
}

List<Task> buildInitialTasks(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  Task block(String id, String title, DateTime start, DateTime end, List<String> tags) {
    return Task(
      id: id,
      type: TaskType.block,
      title: title,
      tagIds: tags,
      status: TaskStatus.active,
      startAt: start,
      endAt: end,
      remindAt: start.subtract(const Duration(minutes: 15)),
      lastActivityAt: now.subtract(const Duration(hours: 1)),
    );
  }

  Task ddl(String id, String title, DateTime due, List<String> tags, {TaskStatus s = TaskStatus.active}) {
    return Task(
      id: id,
      type: TaskType.ddl,
      title: title,
      tagIds: tags,
      status: s,
      dueAt: due,
      remindAt: due.subtract(const Duration(hours: 1)),
      lastActivityAt: now.subtract(const Duration(hours: 2)),
      completedAtWeekYear: s == TaskStatus.completed ? weekKeyFor(now.subtract(const Duration(days: 1))) : null,
    );
  }

  Task todo(
    String id,
    String title,
    List<String> tags, {
    DateTime? due,
    int? expected,
    List<Subtask> subtasks = const [],
    DateTime? lastAct,
    TaskStatus s = TaskStatus.active,
  }) {
    return Task(
      id: id,
      type: TaskType.todo,
      title: title,
      tagIds: tags,
      status: s,
      dueAt: due,
      expectedMinutes: expected,
      remindAt: due?.subtract(const Duration(hours: 2)),
      subtasks: subtasks,
      focusTotalSeconds: 1800,
      lastActivityAt: lastAct ?? now.subtract(const Duration(minutes: 30)),
      completedAtWeekYear: s == TaskStatus.completed ? weekKeyFor(now) : null,
    );
  }

  return [
    block(
      't_block_1',
      '项目周会',
      today.add(const Duration(hours: 10)),
      today.add(const Duration(hours: 11)),
      const ['tag_learn', 'tag_work', 'tag_life', 'tag_other'],
    ),
    ddl(
      't_ddl_1',
      '线代作业提交',
      tomorrow.add(const Duration(hours: 16)),
      const ['tag_learn'],
    ),
    todo(
      't_todo_1',
      '复习线代',
      const ['tag_learn'],
      due: tomorrow,
      expected: 120,
      subtasks: const [
        Subtask(id: 's1', title: '第一章例题', done: true, order: 1),
        Subtask(id: 's2', title: '第二章习题', done: false, order: 2),
      ],
      lastAct: now.subtract(const Duration(minutes: 5)),
    ),
    todo(
      't_todo_2',
      '整理书架',
      const ['tag_life'],
      expected: 45,
      subtasks: const [
        Subtask(id: 's3', title: '上层', done: false, order: 1),
      ],
      lastAct: now.subtract(const Duration(days: 1)),
    ),
    ddl(
      't_ddl_done',
      '上周报告',
      today.subtract(const Duration(days: 3)),
      const ['tag_work'],
      s: TaskStatus.completed,
    ),
    ddl(
      't_ddl_cancel',
      '已取消示例',
      today.add(const Duration(days: 5)),
      const ['tag_life'],
      s: TaskStatus.cancelled,
    ),
    ddl(
      't_ddl_overdue',
      '已超时示例',
      today.subtract(const Duration(days: 1)),
      const ['tag_learn'],
    ),
  ];
}
