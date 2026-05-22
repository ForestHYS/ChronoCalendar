import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 中文日期选择 + 居中滚轮时间选择（Web/移动端均可拖动）。
Future<DateTime?> pickDateTimeZh(BuildContext context, DateTime? initial) async {
  final base = initial ?? DateTime.now();
  final d = await showDatePicker(
    context: context,
    locale: const Locale('zh', 'CN'),
    initialDate: base,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: '选择日期',
    cancelText: '取消',
    confirmText: '确定',
  );
  if (d == null || !context.mounted) return null;

  final picked = await showDialog<TimeOfDay>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CenterTimePickerDialog(
      initial: TimeOfDay(hour: base.hour, minute: base.minute),
    ),
  );
  if (picked == null || !context.mounted) return null;
  return DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
}

class _CenterTimePickerDialog extends StatefulWidget {
  const _CenterTimePickerDialog({required this.initial});

  final TimeOfDay initial;

  @override
  State<_CenterTimePickerDialog> createState() => _CenterTimePickerDialogState();
}

class _CenterTimePickerDialogState extends State<_CenterTimePickerDialog> {
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourC;
  late FixedExtentScrollController _minuteC;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
    _hourC = FixedExtentScrollController(initialItem: _hour);
    _minuteC = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourC.dispose();
    _minuteC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.surfaceContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择时间',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: Row(
                  children: [
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: _hourC,
                        itemExtent: 40,
                        perspective: 0.003,
                        diameterRatio: 1.4,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) => setState(() => _hour = i),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 24,
                          builder: (_, i) => Center(
                            child: Text(
                              '${i.toString().padLeft(2, '0')} 时',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: i == _hour ? FontWeight.w700 : FontWeight.w400,
                                color: i == _hour
                                    ? AppColors.onSurface
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListWheelScrollView.useDelegate(
                        controller: _minuteC,
                        itemExtent: 40,
                        perspective: 0.003,
                        diameterRatio: 1.4,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) => setState(() => _minute = i),
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: 60,
                          builder: (_, i) => Center(
                            child: Text(
                              '${i.toString().padLeft(2, '0')} 分',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: i == _minute ? FontWeight.w700 : FontWeight.w400,
                                color: i == _minute
                                    ? AppColors.onSurface
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        TimeOfDay(hour: _hour, minute: _minute),
                      ),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
