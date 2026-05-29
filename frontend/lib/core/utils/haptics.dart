import 'package:flutter/services.dart';

/// 任务标记完成时的触觉反馈。
void hapticTaskCompleted() {
  HapticFeedback.mediumImpact();
}

/// 提醒到点弹出时的触觉反馈。
void hapticReminderTriggered() {
  for (var i = 0; i < 2; i++) {
    HapticFeedback.heavyImpact();
  }
}
