import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/task.dart';
import '../utils/calendar_task_layout.dart';
import 'calendar_task_block.dart';

class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.selectedDate,
    required this.tasks,
    required this.repo,
    required this.onDateSelected,
  });

  final DateTime selectedDate;
  final List<Task> tasks;
  final TaskRepository repo;
  final ValueChanged<DateTime> onDateSelected;

  static const int _startHour = 0;
  static const int _endHour = 24;
  static const double _hourHeight = 32;
  static const double _timeWidth = 36;

  @override
  Widget build(BuildContext context) {
    final weekStart = startOfWeek(selectedDate);
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final weekTasks = tasksForRange(tasks, weekStart, weekEnd);
    final blocks = weekTasks.where((t) => t.type == TaskType.block).toList();
    final markers = weekTasks
        .where((t) => t.type == TaskType.ddl || t.type == TaskType.todo)
        .where((t) => t.dueAt != null)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 170),
      children: [
        _WeekHeader(days: days, selectedDate: selectedDate, onDateSelected: onDateSelected),
        const SizedBox(height: 8),
        _WeekGrid(days: days, blocks: blocks, markers: markers, repo: repo),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.days,
    required this.selectedDate,
    required this.onDateSelected,
  });

  final List<DateTime> days;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        const SizedBox(width: CalendarWeekView._timeWidth),
        ...List.generate(days.length, (i) {
          final day = days[i];
          final selected = sameDay(day, selectedDate);
          return Expanded(
            child: InkWell(
              onTap: () => onDateSelected(day),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      weekLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.onPrimary : AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.days,
    required this.blocks,
    required this.markers,
    required this.repo,
  });

  final List<DateTime> days;
  final List<Task> blocks;
  final List<Task> markers;
  final TaskRepository repo;

  @override
  Widget build(BuildContext context) {
    const height = (CalendarWeekView._endHour - CalendarWeekView._startHour) * CalendarWeekView._hourHeight;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final colW = (c.maxWidth - CalendarWeekView._timeWidth) / 7;
          return Stack(
            children: [
              ...List.generate(CalendarWeekView._endHour - CalendarWeekView._startHour + 1, (i) {
                final top = i * CalendarWeekView._hourHeight;
                final hour = CalendarWeekView._startHour + i;
                return Positioned(
                  left: 0,
                  right: 0,
                  top: top,
                  child: Row(
                    children: [
                      SizedBox(
                        width: CalendarWeekView._timeWidth,
                        child: Text(
                          twoDigits(hour),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
                        ),
                      ),
                      const Expanded(child: Divider(height: 1, color: AppColors.outline)),
                    ],
                  ),
                );
              }),
              ...List.generate(8, (i) {
                final left = CalendarWeekView._timeWidth + i * colW;
                return Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  child: const VerticalDivider(width: 1, color: AppColors.outline),
                );
              }),
              ...blocks.map((task) {
                final start = task.startAt!;
                final end = task.endAt!;
                final dayIndex = days.indexWhere((d) => sameDay(d, start));
                if (dayIndex < 0) return const SizedBox.shrink();
                final dayStart = DateTime(start.year, start.month, start.day, CalendarWeekView._startHour);
                final top = start.difference(dayStart).inMinutes.clamp(0, 24 * 60) / 60 * CalendarWeekView._hourHeight;
                final h = end.difference(start).inMinutes.clamp(30, 6 * 60) / 60 * CalendarWeekView._hourHeight;
                return Positioned(
                  left: CalendarWeekView._timeWidth + dayIndex * colW + 3,
                  width: colW - 6,
                  top: top,
                  height: h.clamp(34.0, 150.0),
                  child: CalendarTaskBlock(
                    task: task,
                    repo: repo,
                    compact: true,
                    onTap: () => context.push('/task/${task.id}'),
                  ),
                );
              }),
              ...markers.map((task) {
                final due = task.dueAt;
                if (due == null) return const SizedBox.shrink();
                final dayIndex = days.indexWhere((d) => sameDay(d, due));
                if (dayIndex < 0) return const SizedBox.shrink();
                final dayStart = DateTime(due.year, due.month, due.day, CalendarWeekView._startHour);
                final top = due.difference(dayStart).inMinutes.clamp(0, 24 * 60) / 60 * CalendarWeekView._hourHeight;
                return Positioned(
                  left: CalendarWeekView._timeWidth + dayIndex * colW - 2,
                  width: colW + 4,
                  top: (top - 16).clamp(0.0, height - 32),
                  child: CalendarDeadlinePin(
                    task: task,
                    compact: true,
                    onTap: () => context.push('/task/${task.id}'),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
