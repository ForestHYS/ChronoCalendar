import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/task_repository.dart';
import '../../../domain/models/tag.dart';

/// 按标签专注占比的环状图；无数据时显示灰色空环。
class TagFocusDonutChart extends StatelessWidget {
  const TagFocusDonutChart({
    super.key,
    required this.slices,
    required this.resolveTag,
    this.dimension = 92,
    this.repaint,
  });

  final List<TagFocusSlice> slices;
  final Tag? Function(String id) resolveTag;
  final double dimension;

  /// 标签列表等变更时强制重绘，避免 CustomPainter 误判不重画。
  final Listenable? repaint;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + b.seconds);
    return SizedBox(
      height: dimension,
      width: dimension,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          resolveTag: resolveTag,
          total: total,
          repaint: repaint,
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
    super.repaint,
  });

  final List<TagFocusSlice> slices;
  final Tag? Function(String id) resolveTag;
  final int total;

  static const _untaggedId = '__untagged__';
  static const _otherId = '__other__';

  Color _colorForSlice(TagFocusSlice s) {
    if (s.tagId == _untaggedId) {
      return const Color(0xFF0D9488);
    }
    if (s.tagId == _otherId) {
      return AppColors.onSurfaceVariant;
    }
    final tag = resolveTag(s.tagId);
    return tag?.color ?? AppColors.chartTagColors[0];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final outer = r * 0.92;
    final inner = r * 0.58;
    final trackColor = AppColors.outline.withValues(alpha: 0.45);

    // 底环：与分段的内外半径一致；用 evenOdd 保证是「环」而非整圆填充异常
    _drawDonutTrack(canvas, c, inner, outer, trackColor);

    if (total > 0) {
      final positive = [for (final s in slices) if (s.seconds > 0) s];
      // 单一标签占满 100% 时 sweep=2π 会使 arcTo 整圈退化，改为整环填充。
      if (positive.length == 1) {
        _drawDonutTrack(canvas, c, inner, outer, _colorForSlice(positive.first));
      } else {
        var start = -math.pi / 2;
        for (final s in slices) {
          if (s.seconds <= 0) continue;
          final sweep = (s.seconds / total) * 2 * math.pi;
          final color = _colorForSlice(s);
          _drawRingSegment(canvas, c, inner, outer, start, sweep, color);
          start += sweep;
        }
      }
    }

    final hole = Paint()..color = AppColors.surfaceContainer;
    canvas.drawCircle(c, inner - 0.5, hole);
  }

  /// 与 `_drawRingSegment` 相同内外半径的完整圆环（灰色轨道 / 无数据时占位）。
  void _drawDonutTrack(
    Canvas canvas,
    Offset center,
    double innerR,
    double outerR,
    Color color,
  ) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: outerR))
      ..addOval(Rect.fromCircle(center: center, radius: innerR));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
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
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
