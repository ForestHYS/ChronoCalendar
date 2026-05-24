import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/notifications/notification_service.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 通知子系统初始化失败不应阻断主流程：app 仍可正常使用，只是不调度提醒
  try {
    await NotificationService.instance.init();
  } catch (e, st) {
    debugPrint('NotificationService.init failed: $e\n$st');
  }
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const CalendarApp(),
    ),
  );
}
