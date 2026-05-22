enum CalendarViewMode {
  day,
  week,
  month,
}

extension CalendarViewModeLabel on CalendarViewMode {
  String get label {
    return switch (this) {
      CalendarViewMode.day => '日',
      CalendarViewMode.week => '周',
      CalendarViewMode.month => '月',
    };
  }
}
