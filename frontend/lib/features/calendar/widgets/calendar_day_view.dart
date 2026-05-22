import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/task.dart';
import '../utils/calendar_task_layout.dart';
import 'calendar_task_block.dart';

class CalendarDayView extends StatelessWidget {
  const CalendarDayView({
    super.key,
    required this.selectedDate,
    required this.tasks,
    required this.repo,
  });

  final DateTime selectedDate;
  final List<Task> tasks;
  final TaskRepository repo;

  static const int _startHour = 0;
  static const int _endHour = 24;
  static const double _hourHeight = 38;
  static const double _timeWidth = 50;

  @override
  Widget build(BuildContext context) {
    final dayTasks = tasksForDay(tasks, selectedDate);
    final timed = dayTasks.where((t) => t.type == TaskType.block).toList();
    final deadlines = dayTasks
        .where((t) => t.type == TaskType.ddl || t.type == TaskType.todo)
        .where((t) => t.dueAt != null)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 170),
      children: [
        _DayGrid(
          blocks: timed,
          deadlines: deadlines,
          repo: repo,
          selectedDate: selectedDate,
        ),
      ],
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.blocks,
    required this.deadlines,
    required this.repo,
    required this.selectedDate,
  });

  final List<Task> blocks;
  final List<Task> deadlines;
  final TaskRepository repo;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    const height = (CalendarDayView._endHour - CalendarDayView._startHour) * CalendarDayView._hourHeight;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: Stack(
        children: [
          ...List.generate(CalendarDayView._endHour - CalendarDayView._startHour + 1, (i) {
            final top = i * CalendarDayView._hourHeight;
            final hour = CalendarDayView._startHour + i;
            return Positioned(
              left: 0,
              right: 0,
              top: top,
              child: Row(
                children: [
                  SizedBox(
                    width: CalendarDayView._timeWidth,
                    child: Text(
                      '${twoDigits(hour)}:00',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                    ),
                  ),
                  const Expanded(child: Divider(height: 1, color: AppColors.outline)),
                ],
              ),
            );
          }),
          ...blocks.map((task) {
            final start = task.startAt!;
            final end = task.endAt!;
            final dayStart = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, CalendarDayView._startHour);
            final minutesFromStart = start.difference(dayStart).inMinutes.clamp(0, 24 * 60);
            final duration = end.difference(start).inMinutes.clamp(30, 8 * 60);
            final top = minutesFromStart / 60 * CalendarDayView._hourHeight;
            final h = duration / 60 * CalendarDayView._hourHeight;
            return Positioned(
              left: CalendarDayView._timeWidth + 8,
              right: 10,
              top: top,
              height: h.clamp(38.0, 180.0),
              child: CalendarTaskBlock(
                task: task,
                repo: repo,
                compact: h < 58,
                onTap: () => context.push('/task/${task.id}'),
              ),
            );
          }),
          ...deadlines.map((task) {
            final due = task.dueAt;
            if (due == null) return const SizedBox.shrink();
            final dayStart = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              CalendarDayView._startHour,
            );
            final top = due.difference(dayStart).inMinutes.clamp(0, 24 * 60) / 60 * CalendarDayView._hourHeight;
            return Positioned(
              left: CalendarDayView._timeWidth + 2,
              right: -6,
              top: (top - 18).clamp(0.0, height - 36),
              child: CalendarDeadlinePin(
                task: task,
                onTap: () => context.push('/task/${task.id}'),
              ),
            );
          }),
        ],
      ),
    );
  }
}
