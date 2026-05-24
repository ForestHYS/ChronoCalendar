import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/agent_chat/agent_chat_page.dart';
import '../../features/calendar/calendar_page.dart';
import '../../features/home/home_page.dart';
import '../../features/pomodoro/pomodoro_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/settings/pomodoro_settings_page.dart';
import '../../features/settings/tag_manage_page.dart';
import '../../features/shell/main_shell.dart';
import '../../features/task_detail/task_detail_page.dart';
import '../../features/task_list/task_list_page.dart';
import 'shell_animated_branch_container.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// 暴露根 Navigator key，供 ReminderScheduler 等全局服务弹出对话框/sheet 使用。
GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

final goRouterProvider = Provider<GoRouter>((ref) {
  // 仅通过 refreshListenable 响应登录态；勿 watch authNotifier，避免改昵称等操作重建路由栈
  final auth = ref.read(authNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final loc = state.matchedLocation;
      final onPublicAuth = loc == '/login' || loc == '/register';
      if (!loggedIn && !onPublicAuth) return '/login';
      if (loggedIn && onPublicAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: shellAnimatedBranchContainer,
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: TaskListPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: CalendarPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: SettingsPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/task/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => TaskDetailPage(
          key: const ValueKey<String>('task-route-new'),
          taskId: null,
          initialExtra: state.extra,
        ),
      ),
      GoRoute(
        path: '/task/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TaskDetailPage(
            key: ValueKey<String>('task-route-$id'),
            taskId: id,
          );
        },
      ),
      GoRoute(
        path: '/settings/tags',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TagManagePage(),
      ),
      GoRoute(
        path: '/settings/pomodoro',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PomodoroSettingsPage(),
      ),
      GoRoute(
        path: '/pomodoro',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PomodoroPage(),
      ),
      GoRoute(
        path: '/pomodoro/:taskId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PomodoroPage(taskId: state.pathParameters['taskId']),
      ),
      GoRoute(
        path: '/agent',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AgentChatPage(),
      ),
    ],
  );
});
