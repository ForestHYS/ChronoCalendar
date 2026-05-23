import 'package:flutter/material.dart';

/// 水平滑入 + 淡入，用于 Tab / 视图切换。
class SlideFadeSwitcher extends StatelessWidget {
  const SlideFadeSwitcher({
    super.key,
    required this.child,
    required this.direction,
    this.duration = const Duration(milliseconds: 280),
  });

  final Widget child;
  /// 1：自右向左进入；−1：自左向右进入。
  final int direction;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (widget, animation) {
        final slide = Tween<Offset>(
          begin: Offset(direction.clamp(-1, 1) * 0.12, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: widget),
        );
      },
      child: child,
    );
  }
}
