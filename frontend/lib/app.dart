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
import 'shared/widgets/app_startup_logo_view.dart';

class CalendarApp extends ConsumerStatefulWidget {
  const CalendarApp({super.key});

  @override
  ConsumerState<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends ConsumerState<CalendarApp> with WidgetsBindingObserver {
  bool _schedulerStarted = false;
  bool _consumedLaunchPayload = false;
  ProviderSubscription<bool>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = ref.listenManual<bool>(
      authNotifierProvider.select((a) => a.isLoggedIn),
      (prev, next) {
        if (next) {
          unawaited(_onLoggedIn());
        } else {
          unawaited(_onLoggedOut());
        }
      },
      fireImmediately: false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _bootstrapIfLoggedIn();
      if (!mounted) return;
      await _onLoggedIn();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.close();
    _authSub = null;
    if (_schedulerStarted) {
      unawaited(ref.read(reminderSchedulerProvider).stop());
      _schedulerStarted = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authNotifierProvider).isLoggedIn) {
      unawaited(_purgeAutoDeleteTasks());
    }
  }

  Future<void> _bootstrapIfLoggedIn() async {
    if (!ref.read(authNotifierProvider).isLoggedIn) return;
    try {
      await ref.read(taskRepositoryProvider).bootstrap();
      await _purgeAutoDeleteTasks();
    } catch (_) {}
  }

  Future<void> _purgeAutoDeleteTasks() async {
    final settings = ref.read(appSettingsRepositoryProvider);
    final repo = ref.read(taskRepositoryProvider);
    await repo.purgeExpiredCompletedTasks(settings.autoDeleteCompletedAfterHours);
    await repo.purgeExpiredOverdueTasks(settings.autoDeleteOverdueAfterHours);
  }

  Future<void> _onLoggedIn() async {
    if (!ref.read(authNotifierProvider).isLoggedIn) return;
    if (_schedulerStarted) return;
    _schedulerStarted = true;
    debugPrint('[App] _onLoggedIn fired, starting scheduler');
    unawaited(NotificationService.instance.requestPermissions());
    ref.read(reminderSchedulerProvider).start();
    _maybeHandleLaunchPayload();
  }

  Future<void> _onLoggedOut() async {
    if (!_schedulerStarted) return;
    _schedulerStarted = false;
    await ref.read(reminderSchedulerProvider).stop();
  }

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
    final loggedIn = ref.watch(authNotifierProvider.select((a) => a.isLoggedIn));
    final bootstrapping = ref.watch(taskRepositoryProvider.select((r) => r.isBootstrapping));

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
        final themed = Theme(
          data: Theme.of(context).copyWith(
            textTheme: GoogleFonts.notoSansScTextTheme(base),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        if (!loggedIn || !bootstrapping) return themed;
        return Stack(
          children: [
            themed,
            const Positioned.fill(
              child: AppStartupLogoView(),
            ),
          ],
        );
      },
    );
  }
}
