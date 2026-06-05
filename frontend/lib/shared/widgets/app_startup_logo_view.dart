import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 启动同步时的 Logo：较慢的渐显（透明度 0→1），无文案。
class AppStartupLogoView extends StatefulWidget {
  const AppStartupLogoView({super.key});

  @override
  State<AppStartupLogoView> createState() => _AppStartupLogoViewState();
}

class _AppStartupLogoViewState extends State<AppStartupLogoView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: Image.asset(
            'assets/logo2.png',
            width: 96,
            height: 96,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
