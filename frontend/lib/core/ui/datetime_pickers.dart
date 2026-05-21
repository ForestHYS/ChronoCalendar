import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 中文日期选择 + iOS 风格滚轮时间选择。
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

  final picked = await showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      var hour = base.hour;
      var minute = base.minute;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Text(
                    '选择时间',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: hour),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => hour = i,
                      children: List.generate(
                        24,
                        (i) => Center(child: Text('${i.toString().padLeft(2, '0')} 时')),
                      ),
                    ),
                  ),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(initialItem: minute),
                      itemExtent: 36,
                      onSelectedItemChanged: (i) => minute = i,
                      children: List.generate(
                        60,
                        (i) => Center(child: Text('${i.toString().padLeft(2, '0')} 分')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return null;
  return DateTime(d.year, d.month, d.day, picked.hour, picked.minute);
}
