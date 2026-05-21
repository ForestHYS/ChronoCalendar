import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';

class CalendarApp extends ConsumerStatefulWidget {
  const CalendarApp({super.key});

  @override
  ConsumerState<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends ConsumerState<CalendarApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!ref.read(authNotifierProvider).isLoggedIn) return;
      try {
        await ref.read(taskRepositoryProvider).bootstrap();
      } catch (_) {}
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
