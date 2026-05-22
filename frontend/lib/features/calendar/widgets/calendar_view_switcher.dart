import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/calendar_view_mode.dart';

class CalendarViewSwitcher extends StatelessWidget {
  const CalendarViewSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CalendarViewMode value;
  final ValueChanged<CalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CalendarViewMode>(
      segments: CalendarViewMode.values
          .map(
            (mode) => ButtonSegment<CalendarViewMode>(
              value: mode,
              label: Text(mode.label),
            ),
          )
          .toList(),
      selected: {value},
      onSelectionChanged: (next) => onChanged(next.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.surfaceContainerHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return AppColors.onSurfaceVariant;
        }),
        side: WidgetStateProperty.all(const BorderSide(color: AppColors.outline)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}
