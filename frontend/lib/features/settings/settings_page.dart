import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/ui/app_error_dialog.dart';
import '../../data/providers.dart';
import '../../shared/widgets/app_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authRepo = ref.watch(authRepositoryProvider);
    final taskRepo = ref.watch(taskRepositoryProvider);
    final email = authRepo.savedEmail ?? '未登录';
    final nickname = authRepo.nickname;
    final completedTotal = taskRepo.countCompletedTotal();
    final focusSeconds = taskRepo.lastWeekTotalFocusSeconds();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'AI 助手',
            onPressed: () => context.push('/agent'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _showEditNickname(context, ref),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        minimumSize: const Size(0, 38),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('改昵称', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('修改密码'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showChangePassword(context, ref),
                ),
                const Divider(height: 1, color: AppColors.outline),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('编辑备选标签'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/tags'),
                ),
                const Divider(height: 1, color: AppColors.outline),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('番茄钟设置'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/pomodoro'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _AchievementSection(
            completedTotal: completedTotal,
            focusSeconds: focusSeconds,
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('退出登录'),
              onTap: () async {
                await ref.read(authNotifierProvider).logout();
                if (!context.mounted) return;
                context.go('/login');
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showEditNickname(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(authRepositoryProvider);
    final c = TextEditingController(text: repo.nickname);
    final nav = Navigator.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('修改昵称'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: '昵称'),
          ),
          actions: [
            TextButton(onPressed: () => dialogContext.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () async {
                try {
                  await ref.read(authRepositoryProvider).updateNickname(c.text);
                  nav.pop();
                } catch (e) {
                  if (!context.mounted) return;
                  await showAppErrorDialog(context, title: '保存失败', error: e);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showChangePassword(BuildContext context, WidgetRef ref) async {
    final currentC = TextEditingController();
    final nextC = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('修改密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentC,
                decoration: const InputDecoration(labelText: '当前密码'),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nextC,
                decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => dialogContext.pop(), child: const Text('取消')),
            OutlinedButton(
              onPressed: () async {
                try {
                  await ref.read(authRepositoryProvider).changePassword(
                        current: currentC.text,
                        next: nextC.text,
                      );
                  nav.pop();
                  messenger.showSnackBar(const SnackBar(content: Text('密码已更新')));
                } catch (e) {
                  if (!context.mounted) return;
                  await showAppErrorDialog(context, title: '修改失败', error: e);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}

class _AchievementSection extends StatefulWidget {
  const _AchievementSection({
    required this.completedTotal,
    required this.focusSeconds,
  });

  final int completedTotal;
  final int focusSeconds;

  @override
  State<_AchievementSection> createState() => _AchievementSectionState();
}

class _AchievementSectionState extends State<_AchievementSection> with TickerProviderStateMixin {
  bool _expanded = false;

  List<_Achievement> _items() {
    final focusHours = widget.focusSeconds / 3600.0;
    return <_Achievement>[
      _Achievement(
        title: '新手上路',
        subtitle: '完成 1 个任务',
        icon: Icons.emoji_events_outlined,
        unlocked: widget.completedTotal >= 1,
      ),
      _Achievement(
        title: '坚持不懈',
        subtitle: '完成 10 个任务',
        icon: Icons.military_tech_outlined,
        unlocked: widget.completedTotal >= 10,
      ),
      _Achievement(
        title: '效率达人',
        subtitle: '完成 30 个任务',
        icon: Icons.workspace_premium_outlined,
        unlocked: widget.completedTotal >= 30,
      ),
      _Achievement(
        title: '专注 1 小时',
        subtitle: '上周累计 ≥ 1h',
        icon: Icons.timer_outlined,
        unlocked: focusHours >= 1,
      ),
      _Achievement(
        title: '专注 5 小时',
        subtitle: '上周累计 ≥ 5h',
        icon: Icons.timelapse_outlined,
        unlocked: focusHours >= 5,
      ),
      _Achievement(
        title: '心流状态',
        subtitle: '上周累计 ≥ 20h',
        icon: Icons.auto_awesome_outlined,
        unlocked: focusHours >= 20,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final visible = _expanded ? items : items.take(4).toList();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Text(
                    '成就勋章',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final itemW = (w - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in visible)
                      SizedBox(
                        width: itemW,
                        child: _AchievementCard(a: a),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Achievement {
  const _Achievement({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.unlocked,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool unlocked;
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.a});

  final _Achievement a;

  @override
  Widget build(BuildContext context) {
    final bg = a.unlocked ? Colors.white : AppColors.surfaceContainerHigh;
    final border = a.unlocked ? AppColors.outline : AppColors.outline.withValues(alpha: 0.55);
    final iconColor = a.unlocked ? AppColors.primary : AppColors.onSurfaceVariant;
    final titleColor = a.unlocked ? AppColors.onSurface : AppColors.onSurfaceVariant;
    final subColor = AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: a.unlocked ? AppColors.primaryContainer : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
            ),
            child: Icon(a.icon, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: titleColor, height: 1.1),
                ),
                const SizedBox(height: 4),
                Text(
                  a.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: subColor, height: 1.2),
                ),
              ],
            ),
          ),
          if (!a.unlocked)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
