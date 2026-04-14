import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 专注统计示意：堆叠柱状图（演示数据来自 Repository）。
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.stacks,
  });

  final List<List<double>> stacks;

  static const _maxH = 96.0;
  static const _norm = 3.2;

  @override
  Widget build(BuildContext context) {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
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
          height: _maxH + 28,
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
                        height: _maxH,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            ...List.generate(parts.length, (i) {
                              final h = _maxH * (parts[i] / _norm);
                              return Positioned(
                                bottom: _stackBottom(parts, i, _maxH, _norm),
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: h.clamp(4.0, _maxH),
                                  decoration: BoxDecoration(
                                    color: AppColors
                                        .chartTagColors[i % AppColors.chartTagColors.length],
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
    );
  }

  double _stackBottom(List<double> parts, int index, double maxH, double norm) {
    var bottom = 0.0;
    for (var i = 0; i < index; i++) {
      bottom += maxH * (parts[i] / norm);
    }
    return bottom;
  }
}
