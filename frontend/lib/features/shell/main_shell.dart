import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/shell_nav_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with SingleTickerProviderStateMixin {
  late AnimationController _indicatorController;
  Animation<double> _indicatorAnim =
      AlwaysStoppedAnimation<double>(0);

  @override
  void initState() {
    super.initState();
    final idx = widget.navigationShell.currentIndex.toDouble();
    _indicatorController = AnimationController(
      vsync: this,
      duration: kShellNavAnimationDuration,
    );
    _indicatorAnim = AlwaysStoppedAnimation<double>(idx);
    _indicatorController.value = 1;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIdx = oldWidget.navigationShell.currentIndex;
    final newIdx = widget.navigationShell.currentIndex;
    if (oldIdx != newIdx) {
      _indicatorAnim = Tween<double>(
        begin: oldIdx.toDouble(),
        end: newIdx.toDouble(),
      ).animate(
        CurvedAnimation(
          parent: _indicatorController,
          curve: Curves.easeOutCubic,
        ),
      );
      _indicatorController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _indicatorController.dispose();
    super.dispose();
  }

  void _goBranch(int index) {
    final current = widget.navigationShell.currentIndex;
    if (current == index) return;
    ref.read(shellNavDirectionProvider.notifier).state = index > current ? 1 : -1;
    widget.navigationShell.goBranch(index);
    if (index == 0) {
      ref.read(homeTabReselectedProvider.notifier).state++;
    }
  }

  /// 各 Tab 中心 x（与 Row 中四个 [Expanded] + 中间 [SizedBox(width: 72)] 一致）。
  static double _tabCenterX(double index, double totalWidth) {
    const gap = 72.0;
    final sw = (totalWidth - gap) / 4;
    double c(int k) => k * sw + (k >= 2 ? gap : 0) + sw / 2;
    if (index <= 0) return c(0);
    if (index >= 3) return c(3);
    final i = index.floor();
    final f = index - i;
    return c(i) + f * (c(i + 1) - c(i));
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;

    return Scaffold(
      body: shell,
      extendBody: true,
      floatingActionButton: SizedBox(
        width: 56,
        height: 56,
        child: FloatingActionButton(
          onPressed: () => context.push('/task/new'),
          elevation: 2,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 64,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        color: AppColors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  label: '主页',
                  selected: shell.currentIndex == 0,
                  onTap: () => _goBranch(0),
                ),
                _NavItem(
                  icon: Icons.list_alt_outlined,
                  label: '任务',
                  selected: shell.currentIndex == 1,
                  onTap: () => _goBranch(1),
                ),
                const SizedBox(width: 72),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  label: '日历',
                  selected: shell.currentIndex == 2,
                  onTap: () => _goBranch(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  label: '我的',
                  selected: shell.currentIndex == 3,
                  onTap: () => _goBranch(3),
                ),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        const gap = 72.0;
                        final sw = (w - gap) / 4;
                        final pillW = sw * 0.48;

                        return AnimatedBuilder(
                          animation: _indicatorController,
                          builder: (context, child) {
                            final d = _indicatorAnim.value;
                            final cx = _tabCenterX(d, w);
                            final left = (cx - pillW / 2).clamp(0.0, w - pillW);

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: left,
                                  width: pillW,
                                  height: 3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
