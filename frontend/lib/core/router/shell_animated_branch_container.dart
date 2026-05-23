import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import 'shell_nav_constants.dart';

/// 保留各分支 Navigator 状态（全部挂载在 [Offstage] 下），并在 Tab 切换时左右横滑 + 淡入淡出。
Widget shellAnimatedBranchContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  final dir = ProviderScope.containerOf(context).read(shellNavDirectionProvider);
  return _AnimatedBranchStack(
    currentIndex: navigationShell.currentIndex,
    direction: dir == 0 ? 1 : dir,
    children: children,
  );
}

class _AnimatedBranchStack extends StatefulWidget {
  const _AnimatedBranchStack({
    required this.currentIndex,
    required this.direction,
    required this.children,
  });

  final int currentIndex;
  final int direction;
  final List<Widget> children;

  @override
  State<_AnimatedBranchStack> createState() => _AnimatedBranchStackState();
}

class _AnimatedBranchStackState extends State<_AnimatedBranchStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _t;
  int _outgoingIndex = 0;

  @override
  void initState() {
    super.initState();
    _outgoingIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: kShellNavAnimationDuration,
    );
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _outgoingIndex = oldWidget.currentIndex;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final dir = widget.direction >= 0 ? 1 : -1;
        final incoming = widget.currentIndex;
        final outgoing = _outgoingIndex;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _t.value;
            final animating = outgoing != incoming && t < 1.0 - 1e-5;

            // 绘制顺序：隐藏层 → 退场页 → 进场页（在上层）
            final paintOrder = <int>[
              for (var i = 0; i < widget.children.length; i++)
                if (i != incoming && !(animating && i == outgoing)) i,
              if (animating) outgoing,
              incoming,
            ];

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                for (final i in paintOrder)
                  Positioned.fill(
                    child: _slot(
                      index: i,
                      width: w,
                      direction: dir,
                      t: t,
                      animating: animating,
                      incoming: incoming,
                      outgoing: outgoing,
                      child: widget.children[i],
                    ),
                  ),
                if (animating)
                  const Positioned.fill(
                    child: ModalBarrier(
                      color: Colors.transparent,
                      dismissible: false,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _slot({
    required int index,
    required double width,
    required int direction,
    required double t,
    required bool animating,
    required int incoming,
    required int outgoing,
    required Widget child,
  }) {
    final isIncoming = index == incoming;
    final isOutgoing = animating && index == outgoing;
    final hidden = !isIncoming && !isOutgoing;

    Widget body = child;
    if (animating && isOutgoing) {
      body = Transform.translate(
        offset: Offset(-direction * width * t, 0),
        child: Opacity(opacity: 1 - t, child: body),
      );
    } else if (animating && isIncoming) {
      body = Transform.translate(
        offset: Offset(direction * width * (1 - t), 0),
        child: Opacity(opacity: t, child: body),
      );
    }

    final tickerOn = hidden
        ? false
        : animating
            ? (isIncoming ? t >= 0.5 : isOutgoing && t < 0.5)
            : isIncoming;

    return Offstage(
      offstage: hidden,
      child: IgnorePointer(
        ignoring: !isIncoming,
        child: TickerMode(
          enabled: tickerOn,
          child: body,
        ),
      ),
    );
  }
}
