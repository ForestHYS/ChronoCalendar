import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import 'models/calendar_view_mode.dart';
import 'utils/calendar_task_layout.dart';
import 'widgets/calendar_day_view.dart';
import 'widgets/calendar_month_view.dart';
import 'widgets/calendar_view_switcher.dart';
import 'widgets/calendar_week_view.dart';
import 'widgets/todo_timeline_panel.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  CalendarViewMode _mode = CalendarViewMode.week;
  DateTime _selectedDate = DateTime.now();
  bool _todoExpanded = false;

  void _move(int delta) {
    setState(() {
      _selectedDate = switch (_mode) {
        CalendarViewMode.day => _selectedDate.add(Duration(days: delta)),
        CalendarViewMode.week => _selectedDate.add(Duration(days: delta * 7)),
        CalendarViewMode.month => DateTime(
            _selectedDate.year,
            _selectedDate.month + delta,
            _selectedDate.day,
          ),
      };
    });
  }

  void _goToday() {
    setState(() => _selectedDate = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(taskRepositoryProvider);
    final tasks = repo.tasks;
    final todos = todosForTimeline(tasks, DateTime(1970), DateTime(9999));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          TextButton(onPressed: _goToday, child: const Text('今天')),
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'AI 助手',
            onPressed: () => context.push('/agent'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: _CalendarHeader(
                  title: _title,
                  mode: _mode,
                  onPrevious: () => _move(-1),
                  onNext: () => _move(1),
                  onModeChanged: (mode) => setState(() => _mode = mode),
                ),
              ),
              Expanded(
                child: switch (_mode) {
                  CalendarViewMode.day => CalendarDayView(
                      selectedDate: _selectedDate,
                      tasks: tasks,
                      repo: repo,
                    ),
                  CalendarViewMode.week => CalendarWeekView(
                      selectedDate: _selectedDate,
                      tasks: tasks,
                      repo: repo,
                      onDateSelected: (date) => setState(() => _selectedDate = date),
                    ),
                  CalendarViewMode.month => CalendarMonthView(
                      selectedDate: _selectedDate,
                      tasks: tasks,
                      repo: repo,
                      onDateSelected: (date) => setState(() => _selectedDate = date),
                    ),
                },
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 76,
            child: TodoTimelinePanel(
              todos: todos,
              repo: repo,
              expanded: _todoExpanded,
              onToggle: () => setState(() => _todoExpanded = !_todoExpanded),
            ),
          ),
        ],
      ),
    );
  }

  String get _title {
    return switch (_mode) {
      CalendarViewMode.day => '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
      CalendarViewMode.week => _weekTitle,
      CalendarViewMode.month => '${_selectedDate.year}年${_selectedDate.month}月',
    };
  }

  String get _weekTitle {
    final start = startOfWeek(_selectedDate);
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${start.year}年${start.month}月${start.day}日 - ${end.day}日';
    }
    return '${start.year}年${start.month}月${start.day}日 - ${end.month}月${end.day}日';
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.title,
    required this.mode,
    required this.onPrevious,
    required this.onNext,
    required this.onModeChanged,
  });

  final String title;
  final CalendarViewMode mode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<CalendarViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: '上一段',
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: '下一段',
            ),
          ],
        ),
        CalendarViewSwitcher(value: mode, onChanged: onModeChanged),
      ],
    );
  }
}
