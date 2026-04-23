import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/tag.dart';

/// 按标签专注占比的环状图（演示数据）。
class TagFocusDonutChart extends StatelessWidget {
  const TagFocusDonutChart({
    super.key,
    required this.slices,
    required this.resolveTag,
    this.dimension = 92,
  });

  final List<TagFocusSlice> slices;
  final Tag? Function(String id) resolveTag;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + b.seconds);
    if (total <= 0) {
      return SizedBox(
        height: dimension,
        width: dimension,
        child: const Center(
          child: Text('暂无数据', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: dimension,
      width: dimension,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          resolveTag: resolveTag,
          total: total,
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.resolveTag,
    required this.total,
  });

  final List<TagFocusSlice> slices;
  final Tag? Function(String id) resolveTag;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final outer = r * 0.92;
    final inner = r * 0.58;
    var start = -math.pi / 2;

    for (final s in slices) {
      if (s.seconds <= 0) continue;
      final sweep = (s.seconds / total) * 2 * math.pi;
      final tag = resolveTag(s.tagId);
      final color = tag?.color ?? AppColors.chartTagColors[0];
      _drawRingSegment(canvas, c, inner, outer, start, sweep, color);
      start += sweep;
    }

    final hole = Paint()..color = AppColors.surfaceContainer;
    canvas.drawCircle(c, inner - 0.5, hole);
  }

  void _drawRingSegment(
    Canvas canvas,
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweep,
    Color color,
  ) {
    final path = Path()
      ..moveTo(
        center.dx + math.cos(startAngle) * innerR,
        center.dy + math.sin(startAngle) * innerR,
      )
      ..lineTo(
        center.dx + math.cos(startAngle) * outerR,
        center.dy + math.sin(startAngle) * outerR,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerR),
        startAngle,
        sweep,
        false,
      )
      ..lineTo(
        center.dx + math.cos(startAngle + sweep) * innerR,
        center.dy + math.sin(startAngle + sweep) * innerR,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerR),
        startAngle + sweep,
        -sweep,
        false,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.slices != slices || oldDelegate.total != total;
  }
}
