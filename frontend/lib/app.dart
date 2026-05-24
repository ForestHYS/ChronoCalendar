import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';

class CalendarApp extends ConsumerStatefulWidget {
  const CalendarApp({super.key});

  @override
  ConsumerState<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends ConsumerState<CalendarApp> {
  bool _schedulerStarted = false;
  bool _consumedLaunchPayload = false;

  @override
  void initState() {
    super.initState();
    // 监听登录态：登录后启动 scheduler，登出时停止。
    ref.listenManual<bool>(
      authNotifierProvider.select((a) => a.isLoggedIn),
      (prev, next) {
        if (next) {
          _onLoggedIn();
        } else {
          _onLoggedOut();
        }
      },
      fireImmediately: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!ref.read(authNotifierProvider).isLoggedIn) return;
      try {
        await ref.read(taskRepositoryProvider).bootstrap();
      } catch (_) {}
      await _onLoggedIn();
    });
  }

  Future<void> _onLoggedIn() async {
    if (_schedulerStarted) return;
    _schedulerStarted = true;
    debugPrint('[App] _onLoggedIn fired, starting scheduler');
    // 首次登录后请求通知权限（不阻塞 UI）
    unawaited(NotificationService.instance.requestPermissions());
    ref.read(reminderSchedulerProvider).start();
    _maybeHandleLaunchPayload();
  }

  Future<void> _onLoggedOut() async {
    if (!_schedulerStarted) return;
    _schedulerStarted = false;
    await ref.read(reminderSchedulerProvider).stop();
  }

  /// 用户从系统通知冷启动 app 时，跳转到对应任务详情。
  void _maybeHandleLaunchPayload() {
    if (_consumedLaunchPayload) return;
    final id = NotificationService.instance.launchTaskId;
    if (id == null || id.isEmpty) return;
    _consumedLaunchPayload = true;
    NotificationService.instance.launchTaskId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;
      ctx.push('/task/$id');
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: '日程',
      theme: buildAppTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final base = Theme.of(context).textTheme;
        return Theme(
          data: Theme.of(context).copyWith(
            textTheme: GoogleFonts.notoSansScTextTheme(base),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
