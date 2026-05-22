import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/task.dart';
import '../utils/calendar_task_layout.dart';
import 'calendar_task_block.dart';

class CalendarMonthView extends StatelessWidget {
  const CalendarMonthView({
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

  @override
  Widget build(BuildContext context) {
    final selectedTasks = _calendarTasksForDay(tasks, selectedDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 170),
      children: [
        _MonthGrid(
          month: selectedDate,
          selectedDate: selectedDate,
          tasks: tasks,
          onDateSelected: onDateSelected,
        ),
        const SizedBox(height: 10),
        _SelectedDayList(date: selectedDate, tasks: selectedTasks, repo: repo),
      ],
    );
  }
}

List<Task> _calendarTasksForDay(List<Task> tasks, DateTime day) {
  return tasksForDay(tasks, day);
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selectedDate,
    required this.tasks,
    required this.onDateSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final List<Task> tasks;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(month);
    const weekLabels = ['一', '二', '三', '四', '五', '六', '日'];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < weekLabels.length; i++)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.7)),
                        right: i == weekLabels.length - 1
                            ? BorderSide.none
                            : BorderSide(color: AppColors.outline.withValues(alpha: 0.45)),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        weekLabels[i],
                        style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 54,
            ),
            itemBuilder: (context, i) {
              final day = days[i];
              final inMonth = day.month == month.month;
              final selected = sameDay(day, selectedDate);
              final dayTasks = _calendarTasksForDay(tasks, day);
              return InkWell(
                onTap: () => onDateSelected(day),
                borderRadius: BorderRadius.circular(selected ? 10 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryContainer : Colors.transparent,
                    borderRadius: selected ? BorderRadius.circular(10) : null,
                    border: Border(
                      right: (i + 1) % 7 == 0
                          ? BorderSide.none
                          : BorderSide(color: AppColors.outline.withValues(alpha: 0.45)),
                      bottom: i >= 35
                          ? BorderSide.none
                          : BorderSide(color: AppColors.outline.withValues(alpha: 0.45)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: inMonth
                              ? AppColors.onSurface
                              : AppColors.onSurfaceVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 3,
                        runSpacing: 3,
                        children: dayTasks.take(4).map((task) {
                          final color = switch (task.type) {
                            TaskType.block => AppColors.primary,
                            TaskType.ddl => AppColors.error,
                            TaskType.todo => AppColors.success,
                          };
                          return Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SelectedDayList extends StatelessWidget {
  const _SelectedDayList({
    required this.date,
    required this.tasks,
    required this.repo,
  });

  final DateTime date;
  final List<Task> tasks;
  final TaskRepository repo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatMonthDay(date)} 任务',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            const Text(
              '这一天还没有日程或截止任务',
              style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
            )
          else
            ...tasks.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CalendarTaskBlock(
                  task: task,
                  repo: repo,
                  onTap: () => context.push('/task/${task.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
