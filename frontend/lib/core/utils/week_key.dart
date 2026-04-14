/// 简易周键：同一年内按周一为界的周序号，用于「本周完成」演示统计。
int weekKeyFor(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final jan1 = DateTime(d.year, 1, 1);
  final firstMonday = jan1.add(Duration(days: (8 - jan1.weekday) % 7));
  if (day.isBefore(firstMonday)) {
    return d.year * 100 + 1;
  }
  final weeks = day.difference(firstMonday).inDays ~/ 7;
  return d.year * 100 + weeks + 1;
}
