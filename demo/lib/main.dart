import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Tokens aligned with `visual-design.md` (浅色极简).
abstract final class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFDBEAFE);
  static const Color surface = Color(0xFFFAFAFA);
  static const Color surfaceContainer = Color(0xFFFFFFFF);
  static const Color surfaceContainerHigh = Color(0xFFF4F4F5);
  static const Color onSurface = Color(0xFF18181B);
  static const Color onSurfaceVariant = Color(0xFF71717A);
  static const Color outline = Color(0xFFE4E4E7);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFCA8A04);
  static const Color error = Color(0xFFDC2626);

  /// 柱状图 / 标签色带（柔和、可区分）
  static const List<Color> chartTagColors = [
    Color(0xFF3B82F6),
    Color(0xFF06B6D4),
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFF43F5E),
  ];
}

abstract final class AppRadii {
  static const double card = 12;
  static const double chip = 10;
  static const double sheetTop = 16;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: null,
  );
  return base.copyWith(
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: const Color(0xFF1E40AF),
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      outline: AppColors.outline,
    ),
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.outline, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.outline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        minimumSize: const Size(48, 48),
      ),
    ),
  );
}

void main() {
  runApp(const VisualDemoApp());
}

class VisualDemoApp extends StatelessWidget {
  const VisualDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '视觉稿演示',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const VisualShowcasePage(),
    );
  }
}

class VisualShowcasePage extends StatefulWidget {
  const VisualShowcasePage({super.key});

  @override
  State<VisualShowcasePage> createState() => _VisualShowcasePageState();
}

class _VisualShowcasePageState extends State<VisualShowcasePage> {
  int _navIndex = 0;

  void _openReminderPreview() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReminderSheet(onClose: () => Navigator.pop(ctx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '今日概览',
                  style: textTheme.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _StatsCard(
                  completed: 12,
                  pending: 7,
                  cancelled: 1,
                  overdue: 2,
                  topTag: '学习',
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 20)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '本周专注（按标签）',
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _WeeklyBarChart()),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 20)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '今天与明天',
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _TaskRow(
                    title: '项目周会',
                    subtitle: '今天 10:00 – 11:00 · block',
                    tagLabel: '工作',
                    tagColor: AppColors.chartTagColors[0],
                    showComplete: true,
                  ),
                  const SizedBox(height: 8),
                  _TaskRow(
                    title: '线代作业提交',
                    subtitle: '明天 16:00 截止 · ddl',
                    tagLabel: '学习',
                    tagColor: AppColors.chartTagColors[2],
                    showComplete: true,
                  ),
                  const SizedBox(height: 8),
                  _TaskRow(
                    title: '整理书架',
                    subtitle: 'todo · 预计 45 分钟',
                    tagLabel: '生活',
                    tagColor: AppColors.chartTagColors[3],
                    showComplete: false,
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      '标签',
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {},
                      child: const Text('管理'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(label: '学习', selected: true),
                    _FilterChip(label: '娱乐', selected: false),
                    _FilterChip(label: '工作', selected: false),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  onPressed: _openReminderPreview,
                  icon: const Icon(Icons.notifications_outlined, size: 20),
                  label: const Text('预览提醒半屏弹窗样式'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverToBoxAdapter(child: _PomodoroPreview()),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _DemoBottomBar(
        currentIndex: _navIndex,
        onChanged: (i) => setState(() => _navIndex = i),
        onFab: () {},
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.completed,
    required this.pending,
    required this.cancelled,
    required this.overdue,
    required this.topTag,
  });

  final int completed;
  final int pending;
  final int cancelled;
  final int overdue;
  final String topTag;

  @override
  Widget build(BuildContext context) {
    final tabular = const [FontFeature.tabularFigures()];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本周完成',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '$completed',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                height: 1.05,
                color: AppColors.onSurface,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '待完成 $pending  ·  已取消 $cancelled  ·  已超时 $overdue',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                    height: 1.45,
                    fontFeatures: tabular,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '本周最多标签',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Text(
                    topTag,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyBarChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 演示数据：7 天 × 多段堆叠
    final days = ['一', '二', '三', '四', '五', '六', '日'];
    final stacks = <List<double>>[
      [1.2, 0.6, 0.4],
      [0.8, 1.0, 0.2],
      [1.5, 0.3, 0.5],
      [0.4, 0.9, 0.8],
      [1.1, 0.5, 0.9],
      [0.6, 1.2, 0.3],
      [0.9, 0.7, 0.6],
    ];
    const maxH = 96.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(AppColors.chartTagColors.length, (i) {
                if (i >= 3) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.chartTagColors[i],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ['学习', '工作', '娱乐'][i],
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: maxH + 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (d) {
                  final parts = stacks[d];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: maxH,
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                ...List.generate(parts.length, (i) {
                                  final h = maxH * (parts[i] / 3.2);
                                  return Positioned(
                                    bottom: _stackBottom(parts, i, maxH, 3.2),
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: h.clamp(4.0, maxH),
                                      decoration: BoxDecoration(
                                        color: AppColors.chartTagColors[i %
                                            AppColors.chartTagColors.length],
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                          topRight: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            days[d],
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _stackBottom(List<double> parts, int index, double maxH, double norm) {
    double bottom = 0;
    for (var i = 0; i < index; i++) {
      bottom += maxH * (parts[i] / norm);
    }
    return bottom;
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.title,
    required this.subtitle,
    required this.tagLabel,
    required this.tagColor,
    required this.showComplete,
  });

  final String title;
  final String subtitle;
  final String tagLabel;
  final Color tagColor;
  final bool showComplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.outline),
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: tagColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tagLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {},
                  child: const Text('专注'),
                ),
                if (showComplete)
                  TextButton(
                    onPressed: () {},
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.success,
                    ),
                    child: const Text('完成'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryContainer : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(
              color: selected ? AppColors.primary.withOpacity(0.35) : AppColors.outline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? const Color(0xFF1E40AF) : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PomodoroPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tabular = const [FontFeature.tabularFigures()];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          children: [
            Text(
              '番茄钟（示意）',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 20),
            Text(
              '24:38',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
                color: AppColors.onSurface,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '复习线代',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.onSurfaceVariant.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.water_drop_outlined),
                  color: AppColors.onSurfaceVariant,
                  tooltip: '白噪音',
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.park_outlined),
                  color: AppColors.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {},
              child: const Text('结束'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoBottomBar extends StatelessWidget {
  const _DemoBottomBar({
    required this.currentIndex,
    required this.onChanged,
    required this.onFab,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onFab;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, int index) {
      final sel = currentIndex == index;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(index),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: sel ? AppColors.primary : AppColors.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: sel ? AppColors.primary : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Row(
                children: [
                  item(Icons.home_outlined, '主页', 0),
                  item(Icons.list_alt_outlined, '任务', 1),
                  const SizedBox(width: 56),
                  item(Icons.calendar_month_outlined, '日历', 2),
                  item(Icons.person_outline, '我的', 3),
                ],
              ),
              Positioned(
                top: -22,
                child: Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    onTap: onFab,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(Icons.add, color: AppColors.onPrimary, size: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderSheet extends StatelessWidget {
  const _ReminderSheet({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Material(
        color: AppColors.surfaceContainer,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheetTop),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '线代作业提交',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '明天 16:00 截止 · ddl',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onClose,
                child: const Text('启动番茄钟'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onClose,
                child: const Text('标为完成'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClose,
                child: const Text('稍后完成'),
              ),
              TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceVariant),
                child: const Text('任务延期'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
