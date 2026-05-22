import 'package:flutter/material.dart';

/// 日历主体切换动画类型。
enum CalendarBodyTransitionKind {
  /// 同视图内改选中日期（周/月点格），不播放切换动画。
  none,

  /// 顶栏箭头切换日/周/月时间段：左右横切。
  periodSlide,

  /// 日/周/月视图模式切换（分段按钮）。
  modeChange,
}

/// 日历主体 [AnimatedSwitcher]：按 [kind] 选择横切 / 淡入滑入 / 无动画。
class CalendarViewBodySwitcher extends StatelessWidget {
  const CalendarViewBodySwitcher({
    super.key,
    required this.child,
    required this.kind,
    required this.direction,
    this.duration = const Duration(milliseconds: 480),
    this.periodSlideDuration = const Duration(milliseconds: 400),
  });

  final Widget child;
  final CalendarBodyTransitionKind kind;
  /// 1：下一时间段 / 更粗视野；−1：上一时间段 / 更细视野。
  final int direction;
  final Duration duration;
  final Duration periodSlideDuration;

  @override
  Widget build(BuildContext context) {
    if (kind == CalendarBodyTransitionKind.none) {
      return child;
    }

    final slideDuration =
        kind == CalendarBodyTransitionKind.periodSlide ? periodSlideDuration : duration;

    return AnimatedSwitcher(
      duration: slideDuration,
      reverseDuration: slideDuration,
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (widget, animation) {
        if (kind == CalendarBodyTransitionKind.periodSlide) {
          return _buildPeriodSlideTransition(widget, animation);
        }
        return _buildModeChangeTransition(widget, animation);
      },
      child: child,
    );
  }

  Widget _buildPeriodSlideTransition(Widget widget, Animation<double> animation) {
    final dir = direction.clamp(-1, 1).toDouble();
    final isExiting = animation.status == AnimationStatus.reverse;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    final offset = isExiting
        ? Tween<Offset>(begin: Offset.zero, end: Offset(-dir, 0))
        : Tween<Offset>(begin: Offset(dir, 0), end: Offset.zero);

    return ClipRect(
      child: SlideTransition(
        position: offset.animate(curved),
        child: widget,
      ),
    );
  }

  Widget _buildModeChangeTransition(Widget widget, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final dir = direction.clamp(-1, 1);
    final slide = Tween<Offset>(
      begin: Offset(dir * 0.08, 0),
      end: Offset.zero,
    ).animate(curved);

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: slide,
        child: widget,
      ),
    );
  }
}
