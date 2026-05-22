import '../../../domain/models/task.dart';
import '../../../domain/models/task_status.dart';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfWeek(DateTime d) {
  final day = startOfDay(d);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1);

List<DateTime> monthGridDays(DateTime month) {
  final first = startOfMonth(month);
  final gridStart = startOfWeek(first);
  return List.generate(42, (i) => gridStart.add(Duration(days: i)));
}

bool sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool isActiveCalendarTask(Task task) {
  return task.status == TaskStatus.active || task.status == TaskStatus.overdue;
}

bool _inRange(DateTime? value, DateTime from, DateTime to) {
  if (value == null) return false;
  return !value.isBefore(from) && value.isBefore(to);
}

bool _overlaps(DateTime? start, DateTime? end, DateTime from, DateTime to) {
  if (start == null || end == null) return false;
  return start.isBefore(to) && end.isAfter(from);
}

bool taskTouchesRange(Task task, DateTime from, DateTime to) {
  if (!isActiveCalendarTask(task)) return false;
  return switch (task.type) {
    TaskType.block => _overlaps(task.startAt, task.endAt, from, to),
    TaskType.ddl => _inRange(task.dueAt, from, to),
    TaskType.todo => _inRange(task.dueAt, from, to),
  };
}

List<Task> tasksForRange(List<Task> tasks, DateTime from, DateTime to) {
  final out = tasks.where((t) => taskTouchesRange(t, from, to)).toList();
  out.sort((a, b) => taskSortTime(a).compareTo(taskSortTime(b)));
  return out;
}

List<Task> tasksForDay(List<Task> tasks, DateTime day) {
  final from = startOfDay(day);
  return tasksForRange(tasks, from, from.add(const Duration(days: 1)));
}

List<Task> todosForTimeline(List<Task> tasks, DateTime from, DateTime to) {
  final out = tasks.where((t) {
    if (t.type != TaskType.todo || !isActiveCalendarTask(t)) return false;
    return true;
  }).toList();
  out.sort((a, b) => taskSortTime(a).compareTo(taskSortTime(b)));
  return out;
}

int taskSortTime(Task task) {
  final d = switch (task.type) {
    TaskType.block => task.startAt,
    TaskType.ddl => task.dueAt,
    TaskType.todo => task.dueAt,
  };
  return d?.millisecondsSinceEpoch ?? DateTime(9999).millisecondsSinceEpoch;
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

String formatHm(DateTime value) {
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

String formatMonthDay(DateTime value) {
  return '${value.month}/${value.day}';
}
